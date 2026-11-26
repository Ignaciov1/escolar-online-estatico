# ==========================================
# 7. DYNAMODB (CARRITO CON TTL)
# ==========================================
resource "aws_dynamodb_table" "carrito" {
  name         = "carrito-escolaronline"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "productId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "productId"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "carrito-escolaronline" }
}

# ==========================================
# 8. SQS (COLA PRINCIPAL + DLQ)
# ==========================================
resource "aws_sqs_queue" "ordenes_dlq" {
  name                      = "ordenes-escolaronline-dlq"
  message_retention_seconds = 345600
  tags                      = { Name = "ordenes-escolaronline-dlq" }
}

resource "aws_sqs_queue" "ordenes" {
  name                       = "ordenes-escolaronline"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  delay_seconds              = 0

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ordenes_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "ordenes-escolaronline" }
}

# ==========================================
# 9. FUNCIONES LAMBDA (3) + TRIGGER SQS
# ==========================================
data "archive_file" "procesar_carrito" {
  type        = "zip"
  source_file = "${path.module}/../lambda/procesar-carrito/index.js"
  output_path = "${path.module}/../lambda/procesar-carrito.zip"
}

data "archive_file" "crear_orden" {
  type        = "zip"
  source_file = "${path.module}/../lambda/crear-orden/index.js"
  output_path = "${path.module}/../lambda/crear-orden.zip"
}

# Paquete inicial; deploy-automatizado.sh sube luego el zip con mysql2 incluido
data "archive_file" "procesar_orden_bootstrap" {
  type        = "zip"
  source_file = "${path.module}/../lambda/procesar-orden/index.js"
  output_path = "${path.module}/../lambda/procesar-orden-bootstrap.zip"
}

resource "aws_lambda_function" "procesar_carrito" {
  function_name    = "escolaronline-procesar-carrito"
  role             = local.lab_role_arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 30
  filename         = data.archive_file.procesar_carrito.output_path
  source_code_hash = data.archive_file.procesar_carrito.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.carrito.name
    }
  }
}

resource "aws_lambda_function" "crear_orden" {
  function_name    = "escolaronline-crear-orden"
  role             = local.lab_role_arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 30
  filename         = data.archive_file.crear_orden.output_path
  source_code_hash = data.archive_file.crear_orden.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.carrito.name
      QUEUE_URL  = aws_sqs_queue.ordenes.url
    }
  }
}

resource "aws_lambda_function" "procesar_orden" {
  function_name    = "escolaronline-procesar-orden"
  role             = local.lab_role_arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  architectures    = ["arm64"]
  memory_size      = 256
  timeout          = 60
  filename         = data.archive_file.procesar_orden_bootstrap.output_path
  source_code_hash = data.archive_file.procesar_orden_bootstrap.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.priv_app_1a.id, aws_subnet.priv_app_1b.id]
    security_group_ids = [aws_security_group.sg_eks.id]
  }

  environment {
    variables = {
      DB_HOST    = aws_db_instance.escolaronline_db.address
      DB_USER    = var.db_user
      DB_PASS    = var.db_password
      DB_NAME    = var.db_name
      DB_PORT    = "3306"
      TABLE_NAME = aws_dynamodb_table.carrito.name
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_event_source_mapping" "sqs_procesar_orden" {
  event_source_arn = aws_sqs_queue.ordenes.arn
  function_name    = aws_lambda_function.procesar_orden.arn
  batch_size       = 1
}

# ==========================================
# 11. API GATEWAY REST (8 RUTAS + CORS + PROD)
# ==========================================
resource "aws_api_gateway_rest_api" "api" {
  name        = "escolaronline-api"
  description = "API Hibrida EscolarOnline (EKS + Serverless)"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "products"
}

resource "aws_api_gateway_resource" "product_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.products.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "cart" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "cart"
}

resource "aws_api_gateway_resource" "cart_product_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.cart.id
  path_part   = "{productId}"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "orders"
}

# --- 4 Rutas Productos (HTTP Proxy -> ALB EKS) ---
resource "aws_api_gateway_method" "products_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "products_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.products_get.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "http://${var.alb_dns_placeholder}/api/products"
}

resource "aws_api_gateway_method" "products_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "products_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.products_post.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "http://${var.alb_dns_placeholder}/api/products"
}

resource "aws_api_gateway_method" "products_put" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.product_id.id
  http_method        = "PUT"
  authorization      = "NONE"
  request_parameters = { "method.request.path.id" = true }
}

resource "aws_api_gateway_integration" "products_put" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.product_id.id
  http_method             = aws_api_gateway_method.products_put.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "PUT"
  uri                     = "http://${var.alb_dns_placeholder}/api/products/{id}"
  request_parameters      = { "integration.request.path.id" = "method.request.path.id" }
}

resource "aws_api_gateway_method" "products_delete" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.product_id.id
  http_method        = "DELETE"
  authorization      = "NONE"
  request_parameters = { "method.request.path.id" = true }
}

resource "aws_api_gateway_integration" "products_delete" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.product_id.id
  http_method             = aws_api_gateway_method.products_delete.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "DELETE"
  uri                     = "http://${var.alb_dns_placeholder}/api/products/{id}"
  request_parameters      = { "integration.request.path.id" = "method.request.path.id" }
}

# --- 3 Rutas Carrito (Lambda Proxy -> procesar-carrito) ---
resource "aws_api_gateway_method" "cart_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.cart.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cart_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.cart.id
  http_method             = aws_api_gateway_method.cart_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.procesar_carrito.invoke_arn
}

resource "aws_api_gateway_method" "cart_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.cart.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cart_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.cart.id
  http_method             = aws_api_gateway_method.cart_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.procesar_carrito.invoke_arn
}

resource "aws_api_gateway_method" "cart_delete" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.cart_product_id.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cart_delete" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.cart_product_id.id
  http_method             = aws_api_gateway_method.cart_delete.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.procesar_carrito.invoke_arn
}

# --- 1 Ruta Ordenes (Lambda Proxy -> crear-orden) ---
resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "orders_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.orders_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.crear_orden.invoke_arn
}

# --- Permisos de invocacion desde API Gateway a Lambdas ---
resource "aws_lambda_permission" "apigw_procesar_carrito" {
  statement_id  = "AllowAPIGatewayInvokeCart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.procesar_carrito.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_crear_orden" {
  statement_id  = "AllowAPIGatewayInvokeOrders"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crear_orden.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# --- CORS (OPTIONS Mock en los 5 recursos + respuestas 4XX/5XX) ---
locals {
  cors_resources = {
    products        = aws_api_gateway_resource.products.id
    product_id      = aws_api_gateway_resource.product_id.id
    cart            = aws_api_gateway_resource.cart.id
    cart_product_id = aws_api_gateway_resource.cart_product_id.id
    orders          = aws_api_gateway_resource.orders.id
  }
}

resource "aws_api_gateway_method" "cors" {
  for_each      = local.cors_resources
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors" {
  for_each          = local.cors_resources
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = each.value
  http_method       = aws_api_gateway_method.cors[each.key].http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "cors" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "cors" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.cors[each.key].http_method
  status_code = aws_api_gateway_method_response.cors[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.cors,
    aws_api_gateway_method_response.cors
  ]
}

resource "aws_api_gateway_gateway_response" "cors_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_5xx" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  response_type = "DEFAULT_5XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

# --- Deployment y Stage prod ---
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_integration.products_get,
    aws_api_gateway_integration.products_post,
    aws_api_gateway_integration.products_put,
    aws_api_gateway_integration.products_delete,
    aws_api_gateway_integration.cart_get,
    aws_api_gateway_integration.cart_post,
    aws_api_gateway_integration.cart_delete,
    aws_api_gateway_integration.orders_post,
    aws_api_gateway_integration_response.cors
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}