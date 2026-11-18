#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")/.."  # run from the repository root, whatever the caller's directory
# Sync 3D models from Windows host to Kubernetes
# This script pushes local models to the Docker VM
#
# Usage: ./scripts/sync-models-to-k8s.sh

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

# Measure the models directory so the time estimate reflects reality
SIZE_KB=$(du -sk "$LOCAL_MODELS_DIR" | cut -f1)
SIZE_MB=$((SIZE_KB / 1024))
if [ "$SIZE_MB" -ge 1024 ]; then
    SIZE_HUMAN="$((SIZE_MB / 1024)).$(( (SIZE_MB % 1024) * 10 / 1024 ))GB"
else
    SIZE_HUMAN="${SIZE_MB}MB"
fi
# Rough throughput observed: ~4-9 MB/s (tar+gzip piped through kubectl exec)
MIN_MINUTES=$(( SIZE_MB / 540 ))        # ~9 MB/s
MAX_MINUTES=$(( SIZE_MB / 260 + 1 ))    # ~4.3 MB/s
if [ "$MIN_MINUTES" -lt 1 ]; then
    ETA="under $MAX_MINUTES minute(s)"
else
    ETA="$MIN_MINUTES-$MAX_MINUTES minutes"
fi

echo "⬆️  Uploading models (${SIZE_HUMAN}, this may take ~${ETA})..."
cd "$LOCAL_MODELS_DIR" && tar czf - . | kubectl exec -i -n $NAMESPACE $POD -- sh -c '
    mkdir -p /app/priv/static/models && cd /app/priv/static/models && tar xzf -
'

echo ""
echo "✅ Sync complete!"
echo "📁 Models pushed from: $(pwd)"
