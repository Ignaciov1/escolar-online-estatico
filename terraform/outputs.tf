output "account_id" {
  description = "AWS Account ID actual"
  value       = local.account_id
}

output "rds_endpoint" {
  description = "DNS limpio de RDS MySQL (sin el puerto :3306)"
  value       = aws_db_instance.escolaronline_db.address
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
  description = "URL de la cola SQS de órdenes"
  value       = aws_sqs_queue.ordenes.url
}

output "api_gateway_invoke_url" {
  description = "URL base de invocación de API Gateway (stage prod)"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "s3_frontend_bucket" {
  description = "Nombre del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "s3_website_url" {
  description = "URL pública del S3 Static Website"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}