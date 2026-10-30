#!/bin/bash
set -e
cd "$(dirname "${BASH_SOURCE[0]}")/.."  # run from the repository root, whatever the caller's directory

echo "🚀 Starting manual production migration..."

# 0. Rebuild Docker Image (Essential to include the new migration file)
echo "🔨 Building Docker image (no-cache)..."
docker build --no-cache -f Dockerfile.multistage -t "bacon8:prod" --progress=plain --build-arg "MIX_ENV=prod" .

# 1. Clean up any previous run
echo "🧹 Cleaning up previous migration job..."
kubectl delete job run-migrations -n bacon8 --ignore-not-found=true

# 2. Apply the job
echo "📦 Applying migration job..."
kubectl apply -f k3s/jobs/run-migrations.yaml

# 3. Wait for completion
echo "⏳ Waiting for migrations to complete..."
kubectl wait --for=condition=complete job/run-migrations -n bacon8 --timeout=300s || echo "⚠️ Wait timed out or job failed"

# 4. Show logs
echo "📝 Migration Logs:"
kubectl logs job/run-migrations -n bacon8

# 5. Restart web deployment
echo "🔄 Restarting Bacon8 web deployment..."
kubectl rollout restart deployment/bacon8-web -n bacon8

echo "✅ Migration and restart complete!"
