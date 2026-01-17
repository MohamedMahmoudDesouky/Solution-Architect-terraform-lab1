# Add this block at the top of your main.tf
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}



data "aws_availability_zones" "available" {
  state = "available"
}


resource "aws_vpc" "lab1_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "lab1-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.lab1_vpc.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "lab1-public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.lab1_vpc.id
  cidr_block        = "172.16.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "lab1-public-subnet-2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "lab1_igw" {
  vpc_id = aws_vpc.lab1_vpc.id

  tags = {
    Name = "lab1-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab1_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab1_igw.id
  }

  tags = {
    Name = "lab1-public-rt"
  }
}

resource "aws_route_table_association" "rt_assoc_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "rt_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb_sg" {
  name        = "lab1-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.lab1_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab1-alb-sg"
  }
}

resource "aws_security_group" "instance_sg" {
  name        = "lab1-instance-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.lab1_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab1-instance-sg"
  }
}


# ADD this new block
resource "aws_launch_template" "lab1_launch_template" {
  name          = "lab1-launch-template"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  user_data     = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "Hello from $(hostname)!" > /var/www/html/index.html
    EOF
  )

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "lab1-asg-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "lab1_asg" {
  launch_template {
    id      = aws_launch_template.lab1_launch_template.id
    version = "$Latest"
  }
  min_size             = 2
  max_size             = 5
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.public_1.id, aws_subnet.public_2.id] # ← مهم!
  target_group_arns    = [aws_lb_target_group.lab1_target_group.arn]

  tag {
    key                 = "Name"
    value               = "lab1-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_lb" "lab1_alb" {
  name               = "lab1-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id] # ← الحل!

  tags = {
    Name = "lab1-alb"
  }
}

resource "aws_lb_target_group" "lab1_target_group" {
  name        = "lab1-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.lab1_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "lab1-target-group"
  }
}

resource "aws_lb_listener" "lab1_listener" {
  load_balancer_arn = aws_lb.lab1_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab1_target_group.arn
  }
}

resource "aws_cloudwatch_metric_alarm" "lab1_cpu_utilization" {
  alarm_name          = "lab1-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.lab1_asg.name
  }

  alarm_description = "Triggers when CPU > 70% for 4 minutes."
}
