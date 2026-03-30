output "frontend_public_ip"  { value = module.ec2.frontend_public_ip }
output "frontend_private_ip" { value = module.ec2.frontend_private_ip }
output "backend_public_ip"   { value = module.ec2.backend_public_ip }
output "backend_private_ip"  { value = module.ec2.backend_private_ip }
output "ami_id"              { value = data.aws_ami.ubuntu.id }
