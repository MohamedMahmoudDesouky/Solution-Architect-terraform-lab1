terraform {
  backend "s3" {
    bucket = "lab1-terraform-state-selcon-1768599924"  # ← Use your actual $BUCKET value
    key    = "lab1/terraform.tfstate"
    region = "us-east-2"
    encrypt = true
  }
}