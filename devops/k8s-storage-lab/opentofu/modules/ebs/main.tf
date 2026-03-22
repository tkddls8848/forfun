# ── GPFS LUN: NSD-1용 ──
resource "aws_ebs_volume" "gpfs_nsd1" {
  availability_zone = var.availability_zone
  size              = 10
  type              = "gp2"
  tags              = { Name = "${var.project_name}-gpfs-lun-nsd1" }
}

resource "aws_volume_attachment" "gpfs_nsd1" {
  device_name  = "/dev/xvdb"
  volume_id    = aws_ebs_volume.gpfs_nsd1.id
  instance_id  = var.nsd1_instance_id
  force_detach = true
}

# ── GPFS LUN: NSD-2용 ──
resource "aws_ebs_volume" "gpfs_nsd2" {
  availability_zone = var.availability_zone
  size              = 10
  type              = "gp2"
  tags              = { Name = "${var.project_name}-gpfs-lun-nsd2" }
}

resource "aws_volume_attachment" "gpfs_nsd2" {
  device_name  = "/dev/xvdb"
  volume_id    = aws_ebs_volume.gpfs_nsd2.id
  instance_id  = var.nsd2_instance_id
  force_detach = true
}

# ── Ceph OSD: worker 노드당 2개 × 4노드 = 8개 ──
resource "aws_ebs_volume" "ceph_osd_a" {
  count             = 4
  availability_zone = var.availability_zone
  size              = 20
  type              = "gp2"
  tags              = { Name = "${var.project_name}-ceph-osd-${count.index + 1}-a" }
}

resource "aws_ebs_volume" "ceph_osd_b" {
  count             = 4
  availability_zone = var.availability_zone
  size              = 20
  type              = "gp2"
  tags              = { Name = "${var.project_name}-ceph-osd-${count.index + 1}-b" }
}

resource "aws_volume_attachment" "ceph_osd_a" {
  count        = 4
  device_name  = "/dev/xvdb"
  volume_id    = aws_ebs_volume.ceph_osd_a[count.index].id
  instance_id  = var.worker_instance_ids[count.index]
  force_detach = true
}

resource "aws_volume_attachment" "ceph_osd_b" {
  count        = 4
  device_name  = "/dev/xvdc"
  volume_id    = aws_ebs_volume.ceph_osd_b[count.index].id
  instance_id  = var.worker_instance_ids[count.index]
  force_detach = true
}
