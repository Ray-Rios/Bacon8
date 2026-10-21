#!/bin/bash

# Sync uploads from Windows host to Kubernetes
# This script pushes local uploads to the Docker VM
#
# Usage: ./sync-uploads-to-k8s.sh --replace-production-uploads
#
# DANGER: this deletes EVERY file in production uploads (drive files, avatars,
# attachments) and replaces them with the local folder. Anything uploaded since
# the local copy was taken is lost. To remove a few files, delete them in the pod.

set -e

if [ "${1:-}" != "--replace-production-uploads" ]; then
    echo "Refusing: this deletes every file in production uploads and replaces them"
    echo "with ./uploads. Pull first (./sync-uploads-from-k8s.sh), then run:"
    echo "  $0 --replace-production-uploads"
    exit 1
fi

NAMESPACE="bacon8"
LOCAL_UPLOADS_DIR="./uploads"

echo "🔄 Syncing uploads from Windows to Kubernetes..."
echo "================================================"

# Check if local uploads directory exists
if [ ! -d "$LOCAL_UPLOADS_DIR" ]; then
    echo "❌ Error: $LOCAL_UPLOADS_DIR directory not found"
    exit 1
fi

# Get a running bacon8 pod
POD=$(kubectl get pod -n $NAMESPACE -l app=bacon8-web -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "❌ Error: No bacon8-web pod found"
    exit 1
fi

echo "📦 Using pod: $POD"

# Remove existing uploads directory in pod
echo "🗑️  Removing old uploads..."
kubectl exec -n $NAMESPACE $POD -- sh -c 'rm -rf /app/uploads/*'

# Sync uploads from Windows to pod
echo "⬆️  Uploading uploads..."
cd "$LOCAL_UPLOADS_DIR" && tar czf - . | kubectl exec -i -n $NAMESPACE $POD -- sh -c '
    cd /app/uploads && tar xzf -
'

echo ""
echo "✅ Sync complete!"
echo "📁 Uploads pushed from: $(pwd)/$LOCAL_UPLOADS_DIR"
