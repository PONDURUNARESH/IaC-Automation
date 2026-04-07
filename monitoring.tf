# -------------------------
# Security Group for Monitoring
# -------------------------
module "monitoring_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "monitoring-sg"
  description = "Security Group for Prometheus and Grafana"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 9090
      to_port     = 9090
      protocol    = "tcp"
      description = "Prometheus UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      description = "Grafana UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 9100
      to_port     = 9100
      protocol    = "tcp"
      description = "Node Exporter (from within VPC only)"
      cidr_blocks = var.vpc_cidr
    },
    {
      from_port   = 9093
      to_port     = 9093
      protocol    = "tcp"
      description = "Alertmanager UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH Access"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Name        = "monitoring-sg"
    Terraform   = "true"
    Environment = "dev"
  }
}

# -------------------------
# Monitoring EC2 Instance
# -------------------------
module "monitoring_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "Monitoring-Server"

  ami                         = data.aws_ami.example.id
  instance_type               = var.monitoring_instance_type
  key_name                    = aws_key_pair.jenkins.key_name
  monitoring                  = true
  vpc_security_group_ids      = [module.monitoring_sg.security_group_id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  user_data                   = templatefile("scripts/monitoring-install.sh", {
    jenkins_private_ip = module.ec2_instance.private_ip
    vpc_cidr           = var.vpc_cidr
    aws_region         = var.aws_region
  })

  depends_on = [module.ec2_instance]

  tags = {
    Name        = "Monitoring-Server"
    Terraform   = "true"
    Environment = "dev"
    Role        = "monitoring"
  }
}

# -------------------------
# Allow Jenkins EC2 to be scraped by Prometheus
# Adds port 9100 ingress to existing Jenkins SG
# -------------------------
resource "aws_security_group_rule" "jenkins_node_exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = module.monitoring_sg.security_group_id
  security_group_id        = module.sg.security_group_id
  description              = "Allow Prometheus to scrape Node Exporter on Jenkins"
}
