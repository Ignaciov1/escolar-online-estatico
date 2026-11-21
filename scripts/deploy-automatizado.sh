#!/usr/bin/env bash
set -euo pipefail

# --- Colores y Formato ---
C_BLUE='\e[1;34m'
C_GREEN='\e[1;32m'
C_YELLOW='\e[1;33m'
C_CYAN='\e[1;36m'
C_RESET='\e[0m'

echo -e "${C_BLUE}========================================================================${C_RESET}"
echo -e "${C_CYAN}🚀 DESPLIEGUE AUTOMATIZADO ESCOLARONLINE (EKS + SERVERLESS HIBRIDO) 🚀${C_RESET}"
echo -e "${C_BLUE}========================================================================${C_RESET}\n"

# --- 0. Instalación de Dependencias ---
echo -e "${C_YELLOW}[Paso 0] Verificando e instalando dependencias en Workspace...${C_RESET}"
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y docker.io git unzip zip curl mysql-client jq gettext-base nodejs npm > /dev/null 2>&1

sudo systemctl enable --now docker > /dev/null 2>&1
sudo usermod -aG docker ubuntu || true

if ! command -v aws &> /dev/null; then
    echo -e "   ${C_CYAN}-> Instalando AWS CLI v2 (arm64)...${C_RESET}"
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install > /dev/null
    rm -rf /tmp/awscliv2.zip /tmp/aws
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "   ${C_CYAN}-> Instalando kubectl (arm64)...${C_RESET}"
    KUBECTL_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -s -Lo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/arm64/kubectl"
    chmod +x /tmp/kubectl
    sudo mv /tmp/kubectl /usr/local/bin/kubectl
fi
echo -e "${C_GREEN}✔ Dependencias listas.${C_RESET}\n"

# --- Variables Dinámicas ---
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="escolaronline-cluster"
DB_IDENTIFIER="escolaronline-db"
API_NAME="escolaronline-api"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="escolaronline-frontend-${ACCOUNT_ID}"

export AWS_REGION="$REGION"
export ACCOUNT_ID

echo -e "   ${C_CYAN}-> Cuenta AWS: ${C_RESET}${ACCOUNT_ID} | ${C_CYAN}Región: ${C_RESET}${REGION}"

# --- 1. Conexión EKS y Base de Datos RDS ---
echo -e "\n${C_YELLOW}[Paso 1] Conectando a EKS y poblando RDS MySQL (productos + ordenes)...${C_RESET}"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" > /dev/null 2>&1
sudo cp -r ~/.aws /root/ 2>/dev/null || true

NODES=$(aws ec2 describe-instances --region "$REGION" --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
for NODE in $NODES; do
    aws ec2 modify-instance-metadata-options --region "$REGION" --instance-id "$NODE" --http-put-response-hop-limit 2 > /dev/null 2>&1 || true
done

VPC_ID=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" --query "cluster.resourcesVpcConfig.vpcId" --output text)
RDS_ENDPOINT=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_IDENTIFIER" --query "DBInstances[0].Endpoint.Address" --output text)
export RDS_ENDPOINT

echo -e "   ${C_CYAN}-> RDS Endpoint: ${C_RESET}${RDS_ENDPOINT}"
mysql -h "$RDS_ENDPOINT" -u alumno -palumno123 < "$REPO_DIR/init.sql"
echo -e "${C_GREEN}✔ Base de datos escolar_online (productos + ordenes) lista.${C_RESET}\n"

# --- 2. Build y Push de los 4 Microservicios Backend a ECR ---
echo -e "${C_YELLOW}[Paso 2] Compilando y subiendo 4 microservicios CRUD a ECR...${C_RESET}"
aws ecr get-login-password --region "$REGION" | sudo docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com" > /dev/null 2>&1

SERVICES=("get-products" "create-product" "update-product" "delete-product")
for SVC in "${SERVICES[@]}"; do
    REPO="escolaronline-${SVC}"
    echo -e "   ${C_CYAN}-> Build & Push ${REPO}...${C_RESET}"
    aws ecr create-repository --repository-name "$REPO" --region "$REGION" > /dev/null 2>&1 || true
    sudo docker build --network host --platform linux/arm64 -t "$REPO" "$REPO_DIR/microserviciosEKSBackend/$SVC" > /dev/null
    sudo docker tag "${REPO}:latest" "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:latest"
    sudo docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:latest" > /dev/null
done
echo -e "${C_GREEN}✔ 4 imágenes alojadas en ECR.${C_RESET}\n"

# --- 3. Metrics Server y CloudWatch Container Insights (Enhanced) ---
echo -e "${C_YELLOW}[Paso 3] Habilitando Metrics Server y CloudWatch Container Insights...${C_RESET}"
aws eks update-cluster-config --name "$CLUSTER_NAME" --region "$REGION" \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' > /dev/null 2>&1 || true

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml > /dev/null 2>&1 || true
kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s > /dev/null 2>&1 || true

FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
FluentBitReadFromTail='On'
FluentBitHttpServer='On'

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml \
  | sed "s/{{cluster_name}}/${CLUSTER_NAME}/;s/{{region_name}}/${REGION}/;s/{{http_server_toggle}}/\"${FluentBitHttpServer}\"/;s/{{http_server_port}}/\"${FluentBitHttpPort}\"/;s/{{read_from_head}}/\"${FluentBitReadFromHead}\"/;s/{{read_from_tail}}/\"${FluentBitReadFromTail}\"/" \
  | kubectl apply -f - > /dev/null 2>&1 || true

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml > /dev/null 2>&1 || true
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml > /dev/null 2>&1 || true

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
data:
  cwagentconfig.json: |
    {
      "agent": { "region": "${REGION}" },
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "cluster_name": "${CLUSTER_NAME}",
            "metrics_collection_interval": 60,
            "enhanced_container_insights": true
          }
        },
        "force_flush_interval": 5
      }
    }
EOF

kubectl set image daemonset/cloudwatch-agent cloudwatch-agent=public.ecr.aws/cloudwatch-agent/cloudwatch-agent:latest -n amazon-cloudwatch > /dev/null 2>&1 || true
kubectl rollout restart daemonset/cloudwatch-agent -n amazon-cloudwatch > /dev/null 2>&1 || true
kubectl rollout status daemonset/cloudwatch-agent -n amazon-cloudwatch --timeout=90s > /dev/null 2>&1 || true
echo -e "${C_GREEN}✔ Metrics Server y Container Insights activos.${C_RESET}\n"

# --- 4. Renderizar y Desplegar Manifiestos Kubernetes (4 Pods + 4 HPAs) ---
echo -e "${C_YELLOW}[Paso 4] Renderizando y aplicando manifiestos en EKS...${C_RESET}"
mkdir -p "$REPO_DIR/k8s/rendered"
envsubst '${RDS_ENDPOINT}' < "$REPO_DIR/k8s/configmap.yaml" > "$REPO_DIR/k8s/rendered/configmap.yaml"
envsubst '${ACCOUNT_ID} ${AWS_REGION}' < "$REPO_DIR/k8s/deployments.yaml" > "$REPO_DIR/k8s/rendered/deployments.yaml"

kubectl apply -f "$REPO_DIR/k8s/namespace.yaml" > /dev/null
kubectl apply -f "$REPO_DIR/k8s/rendered/configmap.yaml" > /dev/null
kubectl apply -f "$REPO_DIR/k8s/secret.yaml" > /dev/null
kubectl apply -f "$REPO_DIR/k8s/rendered/deployments.yaml" > /dev/null

echo -e "   ${C_CYAN}-> Esperando rollout de los 4 microservicios CRUD...${C_RESET}"
for SVC in "${SERVICES[@]}"; do
    kubectl rollout status "deployment/${SVC}" -n escolaronline --timeout=150s > /dev/null
done
echo -e "${C_GREEN}✔ 4 microservicios CRUD y 4 HPAs activos en namespace escolaronline.${C_RESET}\n"

# --- 5. AWS Load Balancer Controller + IngressClass + ALB Ingress ---
echo -e "${C_YELLOW}[Paso 5] Instalando ALB Controller y aprovisionando Ingress...${C_RESET}"
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.5/cert-manager.yaml > /dev/null 2>&1 || true
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s > /dev/null
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=120s > /dev/null
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s > /dev/null
sleep 10

curl -s -Lo /tmp/v2_5_4_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_full.yaml
curl -s -Lo /tmp/v2_5_4_ingclass.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_ingclass.yaml
sed -i "s/your-cluster-name/${CLUSTER_NAME}/g" /tmp/v2_5_4_full.yaml
sed -i "s/--cluster-name=${CLUSTER_NAME}/--cluster-name=${CLUSTER_NAME}\n        - --aws-region=${REGION}\n        - --aws-vpc-id=${VPC_ID}/g" /tmp/v2_5_4_full.yaml
sed -i 's/replicas: 2/replicas: 1/g' /tmp/v2_5_4_full.yaml

kubectl apply -f /tmp/v2_5_4_full.yaml > /dev/null 2>&1 || true
kubectl apply -f /tmp/v2_5_4_ingclass.yaml > /dev/null 2>&1 || true

AWS_AK=$(awk -F'=' '/aws_access_key_id/ {print $2}' ~/.aws/credentials | tr -d ' \r')
AWS_SK=$(awk -F'=' '/aws_secret_access_key/ {print $2}' ~/.aws/credentials | tr -d ' \r')
AWS_ST=$(awk -F'=' '/aws_session_token/ {print $2}' ~/.aws/credentials | tr -d ' \r')

kubectl set env deployment aws-load-balancer-controller -n kube-system \
  AWS_ACCESS_KEY_ID="$AWS_AK" \
  AWS_SECRET_ACCESS_KEY="$AWS_SK" \
  AWS_SESSION_TOKEN="$AWS_ST" > /dev/null 2>&1 || true

kubectl rollout status deployment aws-load-balancer-controller -n kube-system --timeout=180s > /dev/null
sleep 10

for i in {1..5}; do
    if kubectl apply -f "$REPO_DIR/k8s/ingress.yaml" > /dev/null 2>&1; then
        break
    fi
    echo -e "   ${C_YELLOW}-> Esperando webhook del ALB Controller (intento ${i}/5)...${C_RESET}"
    sleep 10
done

echo -e "   ${C_CYAN}-> Esperando DNS público del ALB...${C_RESET}"
ALB_DNS=""
for i in {1..30}; do
    ALB_DNS=$(kubectl get ingress escolaronline-ingress -n escolaronline -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -n "$ALB_DNS" ]]; then
        break
    fi
    sleep 10
done

if [[ -z "$ALB_DNS" ]]; then
    echo "ERROR: No se obtuvo el DNS del ALB tras esperar 5 minutos."
    exit 1
fi
echo -e "   ${C_CYAN}-> ALB DNS: ${C_RESET}${ALB_DNS}"
echo -e "${C_GREEN}✔ Ingress y ALB aprovisionados.${C_RESET}\n"

# --- 6. Empaquetar y actualizar Lambda procesar-orden (con mysql2) ---
echo -e "${C_YELLOW}[Paso 6] Empaquetando Lambda procesar-orden con mysql2...${C_RESET}"
(
    cd "$REPO_DIR/lambda/procesar-orden"
    npm install --omit=dev --silent > /dev/null 2>&1
    rm -f "$REPO_DIR/lambda/procesar-orden.zip"
    zip -rq "$REPO_DIR/lambda/procesar-orden.zip" index.js package.json node_modules
)
aws lambda update-function-code \
  --region "$REGION" \
  --function-name escolaronline-procesar-orden \
  --zip-file "fileb://${REPO_DIR}/lambda/procesar-orden.zip" > /dev/null
aws lambda wait function-updated --region "$REGION" --function-name escolaronline-procesar-orden
echo -e "${C_GREEN}✔ Lambda procesar-orden actualizada con mysql2.${C_RESET}\n"

# --- 7. Conectar API Gateway al ALB real y subir Frontend a S3 ---
echo -e "${C_YELLOW}[Paso 7] Conectando API Gateway al ALB y desplegando Frontend en S3...${C_RESET}"
API_ID=$(aws apigateway get-rest-apis --region "$REGION" --query "items[?name=='${API_NAME}'].id | [0]" --output text)
PROD_RES_ID=$(aws apigateway get-resources --region "$REGION" --rest-api-id "$API_ID" --query "items[?path=='/api/products'].id | [0]" --output text)
PROD_ID_RES_ID=$(aws apigateway get-resources --region "$REGION" --rest-api-id "$API_ID" --query "items[?path=='/api/products/{id}'].id | [0]" --output text)

aws apigateway update-integration --region "$REGION" --rest-api-id "$API_ID" --resource-id "$PROD_RES_ID" --http-method GET \
  --patch-operations "op=replace,path=/uri,value=http://${ALB_DNS}/api/products" > /dev/null
aws apigateway update-integration --region "$REGION" --rest-api-id "$API_ID" --resource-id "$PROD_RES_ID" --http-method POST \
  --patch-operations "op=replace,path=/uri,value=http://${ALB_DNS}/api/products" > /dev/null
aws apigateway update-integration --region "$REGION" --rest-api-id "$API_ID" --resource-id "$PROD_ID_RES_ID" --http-method PUT \
  --patch-operations "op=replace,path=/uri,value=http://${ALB_DNS}/api/products/{id}" > /dev/null
aws apigateway update-integration --region "$REGION" --rest-api-id "$API_ID" --resource-id "$PROD_ID_RES_ID" --http-method DELETE \
  --patch-operations "op=replace,path=/uri,value=http://${ALB_DNS}/api/products/{id}" > /dev/null

aws apigateway create-deployment --region "$REGION" --rest-api-id "$API_ID" --stage-name prod > /dev/null

API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod"
cat <<EOF > "$REPO_DIR/S3Frontend/js/config.js"
window.APP_CONFIG = {
  API_URL: "${API_URL}"
};
EOF

aws s3 sync "$REPO_DIR/S3Frontend/" "s3://${S3_BUCKET}/" --delete --region "$REGION" > /dev/null
S3_WEBSITE_URL="http://${S3_BUCKET}.s3-website-${REGION}.amazonaws.com"

echo -e "${C_GREEN}✔ API Gateway desplegado y Frontend sincronizado en S3.${C_RESET}\n"

# --- Resumen Final ---
echo -e "${C_BLUE}========================================================================${C_RESET}"
echo -e "${C_CYAN}🎉 DESPLIEGUE COMPLETO FINALIZADO CON ÉXITO 🎉${C_RESET}"
echo -e "${C_YELLOW}Frontend S3 URL :${C_RESET} ${S3_WEBSITE_URL}"
echo -e "${C_YELLOW}API Gateway URL :${C_RESET} ${API_URL}"
echo -e "${C_YELLOW}ALB EKS DNS     :${C_RESET} http://${ALB_DNS}"
echo -e "${C_BLUE}========================================================================${C_RESET}"
echo -e "Tip: espera ~60s a que el ALB pase healthchecks y prueba:"
echo -e "  curl -s ${API_URL}/api/products | jq ."
