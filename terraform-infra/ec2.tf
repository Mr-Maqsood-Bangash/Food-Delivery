# ------------------------------------------------------------------
# Latest Ubuntu 24.04 LTS AMI (Canonical)
# ------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------
# Bastion Host (public subnet)
# ------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/scripts/userdata.sh", {
    repo_url           = var.repo_url
    frontend_node_port = var.frontend_node_port
    green_node_port    = var.green_node_port
  })

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

# ------------------------------------------------------------------
# Private App Server (private subnet — runs kind cluster)
# userdata automatically installs Docker, Kind, kubectl, Helm,
# ArgoCD, ArgoCD CLI, ArgoCD Image Updater, clones the repo,
# creates the kind cluster (with blue + green ports mapped),
# and initiates the MongoDB replica set.
# ------------------------------------------------------------------
resource "aws_instance" "private_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.private_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private_server.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = false

  root_block_device {
    volume_size = 22
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/userdata.sh", {
    repo_url           = var.repo_url
    frontend_node_port = var.frontend_node_port
    green_node_port    = var.green_node_port
  })

  tags = {
    Name = "${var.project_name}-private-server"
  }
}