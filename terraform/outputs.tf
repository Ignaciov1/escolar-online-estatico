output "account_id" {
  description = "AWS Account ID actual"
  value       = local.account_id
}

output "vpc_id" {
  description = "ID de la VPC Multi-AZ (/22) de CleanMarket"
  value       = aws_vpc.eks_vpc.id
}

output "rds_endpoint" {
  description = "DNS limpio de RDS MySQL (sin el puerto :3306)"
  value       = aws_db_instance.cleanmarket_db.address
}

output "eks_cluster_name" {
  description = "Nombre del clúster EKS"
  value       = aws_eks_cluster.eks_cluster.name
}

output "workspace_instance_id" {
  description = "ID de la instancia Workspace para conectar por SSM Session Manager"
  value       = aws_instance.workspace.id
}

output "dynamodb_table_name" {
  description = "Tabla DynamoDB del carrito"
  value       = aws_dynamodb_table.carrito.name
}

output "sqs_queue_url" {
  description = "URL de la cola SQS principal de órdenes"
  value       = aws_sqs_queue.ordenes.url
}

output "sqs_dlq_url" {
  description = "URL de la Dead-Letter Queue (DLQ) de órdenes"
  value       = aws_sqs_queue.ordenes_dlq.url
}

output "api_gateway_invoke_url" {
  description = "URL base de invocación de API Gateway (stage prod)"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "s3_frontend_bucket" {
  description = "Nombre del bucket S3 del frontend"
  value       = "cleanmarket-frontend-${local.account_id}"
}

output "s3_website_url" {
  description = "URL pública del S3 Static Website"
  value       = "http://cleanmarket-frontend-${local.account_id}.s3-website-${var.aws_region}.amazonaws.com"
}

output "cloudwatch_dashboard_name" {
  description = "Nombre del Dashboard de observabilidad en CloudWatch"
  value       = aws_cloudwatch_dashboard.cleanmarket_ops.dashboard_name
}