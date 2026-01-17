# outputs.tf

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.lab1_alb.dns_name
}

output "alb_url" {
  description = "The full HTTP URL to access your application"
  value       = "http://${aws_lb.lab1_alb.dns_name}"
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.lab1_vpc.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_1.id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.lab1_asg.name
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.lab1_target_group.arn
}