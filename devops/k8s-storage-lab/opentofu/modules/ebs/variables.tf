variable "project_name"        { type = string }
variable "availability_zone"   { type = string }
variable "nsd1_instance_id"    { type = string }
variable "nsd2_instance_id"    { type = string }
variable "worker_instance_ids" { type = list(string) }
variable "worker_count" { type = number }
