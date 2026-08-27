variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for naming all resources"
  type        = string
  default     = "food-delivery"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.132.0/24"
}

variable "availability_zones" {
  description = "Two AZs to spread the subnets across (for high availability)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
variable "key_pair_name" {
  description = "Name of an EXISTING EC2 key pair (must already exist in AWS)"
  type        = string
  default     = "kind"
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

variable "private_instance_type" {
  description = "Instance type for the private app server (runs kind cluster)"
  type        = string
  default     = "c7i-flex.large"
}

variable "my_ip_cidr" {
  description = "Your local IP in CIDR form, e.g. '203.0.113.5/32'"
  type        = string
}

variable "frontend_node_port" {
  description = "NodePort the frontend Kubernetes service is exposed on"
  type        = number
  default     = 30007
}

variable "repo_url" {
  description = "Git repository to clone on the private instance"
  type        = string
  default     = "https://github.com/Mr-Maqsood-Bangash/Food-Delivery.git"
}