output "master_public_ips"  { value = module.ec2.master_public_ips }
output "master_private_ips" { value = module.ec2.master_private_ips }
output "worker_public_ips"  { value = module.ec2.worker_public_ips }
output "worker_private_ips" { value = module.ec2.worker_private_ips }
output "nsd_public_ips"     { value = module.ec2.nsd_public_ips }
output "nsd_private_ips"    { value = module.ec2.nsd_private_ips }
output "ami_id"             { value = data.aws_ami.ubuntu.id }
