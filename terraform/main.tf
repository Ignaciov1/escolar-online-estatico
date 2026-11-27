# Obtener Account ID actual para usar LabRole de AWS Academy
data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}

# ==========================================
# 1. VPC (/22) Y SUBREDES (3 CAPAS MULTI-AZ)
# ==========================================
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "cleanmarket-vpc" }
}

resource "aws_subnet" "pub_1a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.0.0/26"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name                                      = "cleanmarket-subnet-pub-1a"
    "kubernetes.io/role/elb"                  = "1"
    "kubernetes.io/cluster/cleanmarket-cluster" = "shared"
  }
}

resource "aws_subnet" "pub_1b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.0.64/26"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = {
    Name                                      = "cleanmarket-subnet-pub-1b"
    "kubernetes.io/role/elb"                  = "1"
    "kubernetes.io/cluster/cleanmarket-cluster" = "shared"
  }
}

resource "aws_subnet" "priv_app_1a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.0/25"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name                                      = "cleanmarket-subnet-priv-app-1a"
    "kubernetes.io/role/internal-elb"         = "1"
    "kubernetes.io/cluster/cleanmarket-cluster" = "shared"
  }
}

resource "aws_subnet" "priv_app_1b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.128/25"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name                                      = "cleanmarket-subnet-priv-app-1b"
    "kubernetes.io/role/internal-elb"         = "1"
    "kubernetes.io/cluster/cleanmarket-cluster" = "shared"
  }
}

resource "aws_subnet" "priv_data_1a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.0/26"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "cleanmarket-subnet-priv-data-1a" }
}

resource "aws_subnet" "priv_data_1b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.64/26"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "cleanmarket-subnet-priv-data-1b" }
}

# ==========================================
# 2. GATEWAYS, TABLAS DE RUTAS Y VPC ENDPOINT
# ==========================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "cleanmarket-igw" }
}

resource "aws_route_table" "rt_pub" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "cleanmarket-rt-pub" }
}

resource "aws_route_table_association" "rta_pub_1a" {
  subnet_id      = aws_subnet.pub_1a.id
  route_table_id = aws_route_table.rt_pub.id
}

resource "aws_route_table_association" "rta_pub_1b" {
  subnet_id      = aws_subnet.pub_1b.id
  route_table_id = aws_route_table.rt_pub.id
}

# --- NAT GATEWAY ZONA A ---
resource "aws_eip" "nat_eip_1a" {
  domain = "vpc"
  tags   = { Name = "cleanmarket-eip-nat-1a" }
}

resource "aws_nat_gateway" "nat_1a" {
  allocation_id = aws_eip.nat_eip_1a.id
  subnet_id     = aws_subnet.pub_1a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "cleanmarket-nat-1a" }
}

resource "aws_route_table" "rt_priv_1a" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1a.id
  }
  tags = { Name = "cleanmarket-rt-priv-1a" }
}

resource "aws_route_table_association" "rta_priv_app_1a" {
  subnet_id      = aws_subnet.priv_app_1a.id
  route_table_id = aws_route_table.rt_priv_1a.id
}

resource "aws_route_table_association" "rta_priv_data_1a" {
  subnet_id      = aws_subnet.priv_data_1a.id
  route_table_id = aws_route_table.rt_priv_1a.id
}

# --- NAT GATEWAY ZONA B ---
resource "aws_eip" "nat_eip_1b" {
  domain = "vpc"
  tags   = { Name = "cleanmarket-eip-nat-1b" }
}

resource "aws_nat_gateway" "nat_1b" {
  allocation_id = aws_eip.nat_eip_1b.id
  subnet_id     = aws_subnet.pub_1b.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "cleanmarket-nat-1b" }
}

resource "aws_route_table" "rt_priv_1b" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1b.id
  }
  tags = { Name = "cleanmarket-rt-priv-1b" }
}

resource "aws_route_table_association" "rta_priv_app_1b" {
  subnet_id      = aws_subnet.priv_app_1b.id
  route_table_id = aws_route_table.rt_priv_1b.id
}

resource "aws_route_table_association" "rta_priv_data_1b" {
  subnet_id      = aws_subnet.priv_data_1b.id
  route_table_id = aws_route_table.rt_priv_1b.id
}

# --- VPC ENDPOINT GATEWAY PARA DYNAMODB ---
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.eks_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.rt_priv_1a.id, aws_route_table.rt_priv_1b.id]
  tags              = { Name = "cleanmarket-dynamodb-endpoint" }
}

# ==========================================
# 3. SECURITY GROUPS (SEGMENTADOS POR CAPA)
# ==========================================
resource "aws_security_group" "sg_alb" {
  name        = "SG-ALB-CleanMarket"
  description = "Capa publica: acceso HTTP/HTTPS al ALB de CleanMarket"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "SG-ALB-CleanMarket" }
}

resource "aws_security_group" "sg_eks" {
  name        = "SG-EKS-CleanMarket"
  description = "Capa de aplicacion: EKS, Workspace y Lambda procesar-orden"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.sg_alb.id]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "SG-EKS-CleanMarket" }
}

resource "aws_security_group" "sg_rds" {
  name        = "SG-RDS-CleanMarket"
  description = "Capa de datos: acceso MySQL 3306 restringido a EKS y Lambda"
  vpc_id      = aws_vpc.eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "SG-RDS-CleanMarket" }
}

resource "aws_security_group_rule" "rds_from_sg_eks" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_rds.id
  source_security_group_id = aws_security_group.sg_eks.id
}

# Permite a los pods del EKS Managed Node Group conectar a RDS por 3306
resource "aws_security_group_rule" "rds_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_rds.id
  source_security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

# ==========================================
# 4. BASE DE DATOS (RDS MYSQL MULTI-AZ CIFRADA)
# ==========================================
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "cleanmarket-rds-subnet-group"
  subnet_ids = [aws_subnet.priv_data_1a.id, aws_subnet.priv_data_1b.id]
  tags       = { Name = "cleanmarket-rds-subnet-group" }
}

resource "aws_db_instance" "cleanmarket_db" {
  identifier              = "cleanmarket-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t4g.small"
  allocated_storage       = 20
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_user
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.sg_rds.id]
  multi_az                = true
  backup_retention_period = 1
  skip_final_snapshot     = true
  publicly_accessible     = false
  tags                    = { Name = "cleanmarket-db" }
}

# ==========================================
# 5. CLUSTER EKS Y NODE GROUP (CON EBS CIFRADO)
# ==========================================
resource "aws_eks_cluster" "eks_cluster" {
  name     = "cleanmarket-cluster"
  role_arn = local.lab_role_arn

  vpc_config {
    subnet_ids = [
      aws_subnet.pub_1a.id,
      aws_subnet.pub_1b.id,
      aws_subnet.priv_app_1a.id,
      aws_subnet.priv_app_1b.id
    ]
    security_group_ids = [aws_security_group.sg_eks.id]
  }

  tags = { Name = "cleanmarket-cluster" }
}

resource "aws_launch_template" "eks_nodes" {
  name_prefix = "cleanmarket-eks-nodes-"
  description = "Launch Template con volumenes EBS gp3 cifrados para nodos EKS CleanMarket"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "cleanmarket-eks-node"
      Project = "CleanMarket-Fintech-SpA"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = "cleanmarket-eks-node-ebs"
      Project = "CleanMarket-Fintech-SpA"
    }
  }
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "cleanmarket-nodes"
  node_role_arn   = local.lab_role_arn
  subnet_ids      = [aws_subnet.priv_app_1a.id, aws_subnet.priv_app_1b.id]
  instance_types  = [var.eks_node_instance_type]
  ami_type        = "AL2023_ARM_64_STANDARD"

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  tags = { Name = "cleanmarket-nodes" }
}

# ==========================================
# 6. INSTANCIA WORKSPACE (SALA DE CONTROL)
# ==========================================
data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
}

resource "aws_instance" "workspace" {
  ami                         = data.aws_ami.ubuntu_arm64.id
  instance_type               = "t4g.small"
  subnet_id                   = aws_subnet.pub_1a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg_eks.id]
  iam_instance_profile        = "LabInstanceProfile"

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y git

              git clone ${var.github_repo_url} /home/ubuntu/cleanmarket
              chmod +x /home/ubuntu/cleanmarket/scripts/*.sh
              chown -R ubuntu:ubuntu /home/ubuntu/cleanmarket

              mkdir -p /home/ubuntu/.aws
              cat << 'EOC' > /home/ubuntu/.aws/credentials
              [default]
              aws_access_key_id = ${var.academy_access_key}
              aws_secret_access_key = ${var.academy_secret_key}
              aws_session_token = ${var.academy_session_token}
              EOC

              cat << 'EOCFG' > /home/ubuntu/.aws/config
              [default]
              region = ${var.aws_region}
              output = json
              EOCFG

              chown -R ubuntu:ubuntu /home/ubuntu/.aws
              EOF

  tags = { Name = "Workspace-EKS-Admin-CleanMarket" }
}