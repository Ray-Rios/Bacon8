#!/bin/bash

# Sync 3D models from Windows host to Kubernetes
# This script pushes local models to the Docker VM
#
# Usage: ./sync-models-to-k8s.sh

set -e

NAMESPACE="bacon8"
LOCAL_MODELS_DIR="./priv/static/models"

echo "🔄 Syncing 3D models from Windows to Kubernetes..."
echo "=================================================="

# Check if local models directory exists
if [ ! -d "$LOCAL_MODELS_DIR" ]; then
    echo "❌ Error: $LOCAL_MODELS_DIR directory not found"
    exit 1
fi

# Get a running bacon8 pod
POD=$(kubectl get pod -n $NAMESPACE -l app=bacon8-web -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "❌ Error: No bacon8-web pod found"
    exit 1
fi

echo "📦 Using pod: $POD"

# Sync models from Windows to pod (may take a few minutes for 2.6GB)
echo "⬆️  Uploading models (this may take 5-10 minutes for 2.6GB)..."
cd "$LOCAL_MODELS_DIR" && tar czf - . | kubectl exec -i -n $NAMESPACE $POD -- sh -c '
    mkdir -p /app/priv/static/models && cd /app/priv/static/models && tar xzf -
'

echo ""
echo "✅ Sync complete!"
echo "📁 Models pushed from: $(pwd)/$LOCAL_MODELS_DIR"
