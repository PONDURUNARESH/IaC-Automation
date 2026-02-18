output "ec2_public_ip" {
  description = "Public IP of Jenkins EC2"
  value       = module.ec2_instance.public_ip
}

output "jenkins_url" {
  description = "Jenkins Web URL"
  value       = "http://${module.ec2_instance.public_ip}:8080"
}

output "private_key_file" {
  description = "Generated PEM Key File"
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "SSH Command"
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${module.ec2_instance.public_ip}"
}
