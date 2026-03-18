variable "project_name"      { type = string }
variable "availability_zone" { type = string }
variable "nsd1_instance_id"  { type = string }
variable "nsd2_instance_id"  { type = string }
variable "ceph_instance_ids" { type = list(string) }
