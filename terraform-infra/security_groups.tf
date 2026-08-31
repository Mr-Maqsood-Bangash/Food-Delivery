# ------------------------------------------------------------------
# Bastion Security Group — SSH only from your IP
# ------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH from admin IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

# ------------------------------------------------------------------
# Private Server Security Group
#   - SSH only from bastion
#   - Blue + Green frontend NodePorts open within VPC for now
#     (ALB-scoped rule replaces this in the ALB task)
# ------------------------------------------------------------------
resource "aws_security_group" "private_server" {
  name        = "${var.project_name}-private-sg"
  description = "Allow SSH from bastion, blue/green app ports open for later ALB integration"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "Blue frontend NodePort (temporary open within VPC, ALB rule replaces this later)"
    from_port   = var.frontend_node_port
    to_port     = var.frontend_node_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Green frontend NodePort (temporary open within VPC, ALB rule replaces this later)"
    from_port   = var.green_node_port
    to_port     = var.green_node_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-private-sg"
  }
}