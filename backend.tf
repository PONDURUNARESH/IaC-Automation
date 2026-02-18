terraform {
  backend "s3" {
    bucket = "cloud-devops-pro1"
    key    = "jenkins/terraform.tfstate"
    region = "us-east-1"
  }
}