#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."  # run from the repository root, whatever the caller's directory

# ---- Parameters ----
ENVIRONMENT="dev"
STREAM_LOGS=true


# ---- Namespace ----
if [[ "$ENVIRONMENT" == "dev" ]]; then
  NAMESPACE="bacon8-dev"
elif [[ "$ENVIRONMENT" == "prod" ]]; then
  NAMESPACE="bacon8"
else
  echo "❌ Invalid environment: $ENVIRONMENT"
  usage
fi

# ---- Pre-flight checks ----
echo "🔍 Running pre-flight checks..."

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed or not in PATH"
    exit 1
fi
echo "✅ Node.js is available"

# Note: Linting is handled by GitHub Actions CI
# Docker build will catch any real compilation errors
echo "✅ Skipping pre-deployment linting (handled by CI)"

# ---- Docker build ----
kubectl delete namespace bacon8-dev --ignore-not-found=true
echo "🧹 Cleaning up old Bacon8 Docker images..."
docker images --filter=reference="bacon8*" -q | xargs -r docker rmi -f || true
echo "🐳 Building Bacon8 Docker image for $ENVIRONMENT..."
docker build -t "bacon8:$ENVIRONMENT" \
              -f Dockerfile.multistage \
              --progress=plain \
              --build-arg "MIX_ENV=$ENVIRONMENT" \
              .

# ---- Kubernetes deployment ----
echo "🚀 Deploying to Kubernetes $ENVIRONMENT environment..."
kubectl apply -f k3s/base/namespace.yaml
kubectl apply -k "k3s/overlays/$ENVIRONMENT/"

echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n "$NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/redis -n "$NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/mailhog -n "$NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/bacon8-web -n "$NAMESPACE"

echo "✅ $ENVIRONMENT environment deployed successfully!"
echo "🌐 Access your application at:"
kubectl get svc bacon8-web -n "$NAMESPACE"


# ---- Optional logs ----
if [[ "$STREAM_LOGS" == true ]]; then
  echo -e "\n📡 Streaming bacon8-web logs (Ctrl+C to stop)..."
  kubectl logs -f -l app=bacon8-web -n "$NAMESPACE" --tail=20
else
  echo -e "\nℹ️ Deployment done. Run with --stream-logs to watch logs."
fi
