# CleanMarket Fintech SpA - Plataforma Cloud Hibrida (EFT ARY1102)

## Descripcion

Plataforma e-commerce moderna para la comercializacion online de productos de higiene y limpieza (hogares, oficinas e industrias), construida sobre AWS con arquitectura hibrida PaaS (Amazon EKS) + Serverless (API Gateway, AWS Lambda, DynamoDB y SQS) automatizada con Terraform y Bash.

## Arquitectura TO-BE

| Capa | Componente | Servicio AWS |
|------|-----------|--------------|
| Red | VPC Multi-AZ 10.0.0.0/22 (6 subredes: 2 Pub, 2 Priv APP, 2 Priv DATA) + IGW + 2 NAT GW + VPC Endpoint Gateway | Amazon VPC |
| Frontend | Sitio web estatico HTML/CSS/JS | Amazon S3 Static Website |
| API | Punto de entrada unico con CORS y Throttling | Amazon API Gateway REST |
| Balanceo | Enrutamiento por metodo HTTP hacia pods CRUD | Application Load Balancer (ALB) |
| Contenedores | 4 microservicios CRUD Node.js + 4 HPAs + EBS cifrado | Amazon EKS + Amazon ECR |
| Serverless | 3 funciones Node.js 20 ARM64 con limites de concurrencia | AWS Lambda |
| Mensajeria | Procesamiento asincrono de ordenes + Dead-Letter Queue (3 reintentos) | Amazon SQS + DLQ |
| BD Relacional | Catalogo de productos, clientes y ordenes (cifrada Multi-AZ) | Amazon RDS MySQL 8.0 |
| BD NoSQL | Carrito temporal con expiracion automatica TTL (expiresAt) | Amazon DynamoDB |
| Observabilidad | Container Insights Enhanced + Logs Lambda/EKS + Dashboard | Amazon CloudWatch |

## Flujo de Despliegue

1. Actualizar credenciales de AWS Academy en terraform/terraform.tfvars y variables de entorno locales.
2. Ejecutar desde terraform/ los comandos terraform init y terraform apply -auto-approve.
3. Conectar por SSM Session Manager a Workspace-EKS-Admin-CleanMarket y ejecutar:
    sudo cloud-init status --wait
    sudo su - ubuntu
    ~/cleanmarket/scripts/deploy-automatizado.sh