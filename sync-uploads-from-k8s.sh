#!/bin/bash

# Sync uploads from Kubernetes to Windows host
# This script extracts all uploads from the Docker VM to your Windows filesystem
#
# Usage: ./sync-uploads-from-k8s.sh

set -e

NAMESPACE="bacon8"
LOCAL_UPLOADS_DIR="./uploads"

echo "🔄 Syncing uploads from Kubernetes to Windows..."
echo "================================================"

# Get a running bacon8 pod
POD=$(kubectl get pod -n $NAMESPACE -l app=bacon8-web -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "❌ Error: No bacon8-web pod found"
    exit 1
fi

echo "📦 Using pod: $POD"

# Create local uploads directory if it doesn't exist
mkdir -p "$LOCAL_UPLOADS_DIR"

# Sync uploads from pod to Windows
echo "⬇️  Downloading uploads..."
kubectl exec -n $NAMESPACE $POD -- sh -c '
    cd /app/uploads && tar czf - .
' | tar xzf - -C "$LOCAL_UPLOADS_DIR"

# Show what was synced
echo ""
echo "✅ Sync complete!"
echo ""
echo "📊 Upload statistics:"
du -sh "$LOCAL_UPLOADS_DIR" 2>/dev/null || echo "N/A"
echo ""
echo "📁 Uploads are now in: $(pwd)/$LOCAL_UPLOADS_DIR"
