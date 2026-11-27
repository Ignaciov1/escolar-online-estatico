#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
PLATFORM="${DOCKER_PLATFORM:-linux/arm64}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== CleanMarket ECR Push | Account: $ACCOUNT_ID | Region: $REGION | Platform: $PLATFORM ==="

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

SERVICES=("get-products" "create-product" "update-product" "delete-product")

for SVC in "${SERVICES[@]}"; do
    REPO="cleanmarket-$SVC"
    aws ecr create-repository --repository-name "$REPO" --region "$REGION" 2>/dev/null || echo "$REPO ya existe"
    docker build --platform "$PLATFORM" -t "$REPO" "$ROOT_DIR/microserviciosEKSBackend/$SVC"
    docker tag "$REPO:latest" "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest"
    docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest"
done

echo "=== Push completado ==="