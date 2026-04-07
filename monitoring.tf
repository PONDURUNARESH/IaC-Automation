# =============================================================================
# monitoring.tf
#
# Strategy: instead of templatefile() (which clashes with bash ${} syntax),
# we write a tiny wrapper inline in user_data that exports Terraform
# values as env vars, embeds monitoring-install.sh verbatim, then runs it.
# =============================================================================

# ── Security Group for Monitoring Server ──────────────────────────────────────
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
      from_port   = 9093
      to_port     = 9093
      protocol    = "tcp"
      description = "Alertmanager UI"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 9100
      to_port     = 9100
      protocol    = "tcp"
      description = "Node Exporter - internal VPC only"
      cidr_blocks = var.vpc_cidr
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
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

# ── Monitoring EC2 Instance ───────────────────────────────────────────────────
# user_data approach (no templatefile):
#   1. Export Terraform-resolved values as env vars
#   2. Embed monitoring-install.sh verbatim using file()
#   3. Run the install script — it reads the env vars
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

  user_data = join("\n", [
    "#!/bin/bash",
    "# Terraform-injected environment variables",
    "export JENKINS_IP='${module.ec2_instance.private_ip}'",
    "export GRAFANA_PASS='${var.grafana_admin_password}'",
    "# monitoring-install.sh (embedded verbatim - no templatefile clash)",
    file("${path.module}/scripts/monitoring-install.sh")
  ])

  depends_on = [module.ec2_instance]

  tags = {
    Name        = "Monitoring-Server"
    Terraform   = "true"
    Environment = "dev"
    Role        = "monitoring"
  }
}

# ── Allow Prometheus to scrape Node Exporter on the Jenkins server ─────────────
resource "aws_security_group_rule" "jenkins_node_exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = module.monitoring_sg.security_group_id
  security_group_id        = module.sg.security_group_id
  description              = "Allow Prometheus (monitoring-sg) to scrape Jenkins Node Exporter"
}
