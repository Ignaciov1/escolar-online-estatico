variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "github_repo_url" {
  description = "URL del repositorio de GitHub de EscolarOnline"
  type        = string
  default     = "https://github.com/Ignaciov1/escolar-online-estatico.git"
}

variable "db_name" {
  description = "Nombre de la base de datos inicial en RDS"
  type        = string
  default     = "escolar_online"
}

variable "db_user" {
  description = "Usuario maestro de RDS"
  type        = string
  default     = "alumno"
}

variable "db_password" {
  description = "Contraseña maestra de RDS"
  type        = string
  default     = "alumno123"
  sensitive   = true
}

variable "eks_node_instance_type" {
  description = "Tipo de instancia ARM64 para el Node Group de EKS"
  type        = string
  default     = "t4g.medium"
}

variable "lambda_runtime" {
  description = "Runtime de Node.js para las funciones Lambda"
  type        = string
  default     = "nodejs20.x"
}

variable "alb_dns_placeholder" {
  description = "DNS temporal para crear API Gateway antes del despliegue de EKS (el script lo actualiza)"
  type        = string
  default     = "example.com"
}

variable "academy_access_key" {
  description = "AWS Access Key temporal de AWS Academy"
  type        = string
  sensitive   = true
}

variable "academy_secret_key" {
  description = "AWS Secret Key temporal de AWS Academy"
  type        = string
  sensitive   = true
}

variable "academy_session_token" {
  description = "AWS Session Token temporal de AWS Academy"
  type        = string
  sensitive   = true
}