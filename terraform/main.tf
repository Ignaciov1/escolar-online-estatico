# Obtener Account ID actual para usar LabRole de AWS Academy
data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}

# ==========================================
# 1. VPC Y SUBREDES (3 CAPAS MULTI-AZ)
# ==========================================
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "escolaronline-vpc" }
}

resource "aws_subnet" "pub_1a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.0.0/26"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "escolaronline-subnet-pub-1a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "pub_1b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.0.64/26"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "escolaronline-subnet-pub-1b"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "priv_app_1a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.0/25"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name                              = "escolaronline-subnet-priv-app-1a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "priv_app_1b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.128/25"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name                              = "escolaronline-subnet-priv-app-1b"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "priv_data_1a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.0/26"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "escolaronline-subnet-priv-data-1a" }
}

resource "aws_subnet" "priv_data_1b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.64/26"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "escolaronline-subnet-priv-data-1b" }
}

# ==========================================
# 2. GATEWAYS, TABLAS DE RUTAS Y VPC ENDPOINT
# ==========================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "escolaronline-igw" }
}

resource "aws_route_table" "rt_pub" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "escolaronline-rt-pub" }
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
  tags   = { Name = "escolaronline-eip-nat-1a" }
}

resource "aws_nat_gateway" "nat_1a" {
  allocation_id = aws_eip.nat_eip_1a.id
  subnet_id     = aws_subnet.pub_1a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "escolaronline-nat-1a" }
}

resource "aws_route_table" "rt_priv_1a" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1a.id
  }
  tags = { Name = "escolaronline-rt-priv-1a" }
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
  tags   = { Name = "escolaronline-eip-nat-1b" }
}

resource "aws_nat_gateway" "nat_1b" {
  allocation_id = aws_eip.nat_eip_1b.id
  subnet_id     = aws_subnet.pub_1b.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "escolaronline-nat-1b" }
}

resource "aws_route_table" "rt_priv_1b" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1b.id
  }
  tags = { Name = "escolaronline-rt-priv-1b" }
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
  tags              = { Name = "escolaronline-dynamodb-endpoint" }
}

# ==========================================
# 3. SECURITY GROUPS
# ==========================================
resource "aws_security_group" "sg_alb" {
  name        = "SG-ALB-EscolarOnline"
  description = "Acceso HTTP/HTTPS publico al ALB"
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

  tags = { Name = "SG-ALB-EscolarOnline" }
}

resource "aws_security_group" "sg_eks" {
  name        = "SG-EKS-EscolarOnline"
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

  tags = { Name = "SG-EKS-EscolarOnline" }
}

resource "aws_security_group" "sg_rds" {
  name        = "SG-RDS-EscolarOnline"
  description = "Capa de datos: acceso MySQL 3306 restringido"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_eks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "SG-RDS-EscolarOnline" }
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
# 4. BASE DE DATOS (RDS MYSQL MULTI-AZ)
# ==========================================
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "escolaronline-rds-subnet-group"
  subnet_ids = [aws_subnet.priv_data_1a.id, aws_subnet.priv_data_1b.id]
  tags       = { Name = "escolaronline-rds-subnet-group" }
}

resource "aws_db_instance" "escolaronline_db" {
  identifier              = "escolaronline-db"
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
  tags                    = { Name = "escolaronline-db" }
}

# ==========================================
# 5. CLUSTER EKS Y NODE GROUP
# ==========================================
resource "aws_eks_cluster" "eks_cluster" {
  name     = "escolaronline-cluster"
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
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "escolaronline-nodes"
  node_role_arn   = local.lab_role_arn
  subnet_ids      = [aws_subnet.priv_app_1a.id, aws_subnet.priv_app_1b.id]
  instance_types  = [var.eks_node_instance_type]
  ami_type        = "AL2023_ARM_64_STANDARD"

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
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

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y git

              git clone ${var.github_repo_url} /home/ubuntu/escolar-online-estatico
              chmod +x /home/ubuntu/escolar-online-estatico/scripts/*.sh
              chown -R ubuntu:ubuntu /home/ubuntu/escolar-online-estatico

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

  tags = { Name = "Workspace-EKS-Admin-EscolarOnline" }
}