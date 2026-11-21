# EscolarOnline — Arquitectura Hibrida Serverless (EA3)

## Descripcion

Evolucion de la aplicacion EscolarOnline hacia un modelo hibrido que combina EKS (CRUD productos) con servicios serverless (carrito + ordenes). Agrega funcionalidades de carrito de compras y procesamiento de ordenes desacoplado.

## Arquitectura TO-BE (Hibrida: EKS + Serverless)

| Capa | Componente | Servicio AWS |
|------|-----------|--------------|
| Frontend | Sitio web estatico | S3 Static Website |
| API | Punto de entrada unico | API Gateway REST |
| Contenedores | CRUD Productos (4 pods) | EKS → RDS MySQL |
| Serverless | Carrito | Lambda Cart → DynamoDB |
| Serverless | Crear orden | Lambda Create-Order → SQS |
| Serverless | Procesar orden | Lambda Process-Order (trigger SQS) → RDS MySQL |
| Mensajeria | Cola ordenes | SQS |
| BD NoSQL | Carrito temporal | DynamoDB (TTL 24h) |
| BD Relacional | Productos + ordenes | RDS MySQL Multi-AZ |

## Estructura de Archivos

```
desarrolloApp-ACT3.3/
├── README.md                          (este archivo)
├── docker-compose.yml                 (prueba local microservicios backend)
├── init.sql                           (schema extendido: productos + ordenes)
├── S3Frontend/
│   ├── index.html                     (con carrito + ordenes)
│   ├── css/styles.css
│   └── js/app.js                      (logica CRUD + carrito + ordenes)
├── microserviciosEKSBackend/
│   ├── get-products/  (Dockerfile, index.js, package.json)
│   ├── create-product/
│   ├── update-product/
│   └── delete-product/
├── lambda/
│   ├── procesar-carrito/
│   │   ├── index.js                   (CRUD carrito → DynamoDB)
│   │   └── package.json
│   ├── crear-orden/
│   │   ├── index.js                   (calcula total → SQS)
│   │   └── package.json
│   └── procesar-orden/
│       ├── index.js                   (consumer SQS → MySQL)
│       └── package.json
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   └── deployments.yaml               (4 pods + services + ingress + HPA)
└── scripts/
    └── ecr-push.sh
```

## Prerequisitos

- Cluster EKS de EA2 funcionando (4 pods CRUD)
- RDS MySQL Multi-AZ de EA2 funcionando
- ALB Ingress de EA2 funcionando
- AWS Academy Learner Lab activo

## Guia de Implementacion

Consultar: **Act-3.3-Anexo-Paso-a-Paso-Implementacion-Serverless.md**

---

2026 - Disenador: Ignacio A. Pastenet M.
