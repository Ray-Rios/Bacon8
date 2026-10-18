#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration
NAMESPACE=${NAMESPACE:-bacon8}
BACKUP_DIR=${BACKUP_DIR:-./backups}
mkdir -p "$BACKUP_DIR"

usage() {
    echo "Usage: $0 {backup|restore|monitor|flush} [NAMESPACE]"
    echo ""
    echo "Commands:"
    echo "  backup   - Create Redis backup"
    echo "  restore  - Restore latest Redis backup"  
    echo "  monitor  - Monitor Redis commands (useful for debugging)"
    echo "  flush    - Flush all Redis data (DANGEROUS!)"
    echo "  keys     - Show Redis keys by pattern"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 restore"
    echo "  $0 monitor"
    echo "  $0 keys 'player:*'"
    echo "  $0 keys 'chat:*'"
    exit 1
}

backup_redis() {
    echo "🔴 Backing up Redis data..."
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    
    if ! kubectl get deployment -n "$NAMESPACE" redis &>/dev/null; then
        print_error "Redis deployment not found in namespace $NAMESPACE"
        exit 1
    fi
    
    REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath="{.items[0].metadata.name}")
    if [ -z "$REDIS_POD" ]; then
        print_error "No Redis pod found"
        exit 1
    fi
    
    # Create backup
    if kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli ping | grep -q PONG; then
        kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli BGSAVE
        echo "Waiting for Redis background save to complete..."
        sleep 10  # Wait for background save
        
        if kubectl cp "$NAMESPACE/$REDIS_POD:/data/dump.rdb" "$BACKUP_DIR/redis_backup_$TIMESTAMP.rdb" 2>/dev/null; then
            # Clean old backups (keep 10)
            ls -t "$BACKUP_DIR"/redis_backup_*.rdb 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
            print_status "Redis backup saved to $BACKUP_DIR/redis_backup_$TIMESTAMP.rdb"
        else
            print_warning "Failed to copy Redis dump file - Redis may be empty or file doesn't exist"
        fi
    else
        print_error "Redis is not responding"
        exit 1
    fi
}

restore_redis() {
    if [ -z "$(find "$BACKUP_DIR" -name "redis_backup_*.rdb" 2>/dev/null)" ]; then
        print_error "No Redis backup files found in $BACKUP_DIR"
        exit 1
    fi
    
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/redis_backup_*.rdb | head -n 1)
    echo "🔴 Restoring Redis from $LATEST_BACKUP..."
    
    REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath="{.items[0].metadata.name}")
    if [ -z "$REDIS_POD" ]; then
        print_error "No Redis pod found"
        exit 1
    fi
    
    # Stop Redis, restore backup, restart
    kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli shutdown nosave || true
    sleep 2
    kubectl cp "$LATEST_BACKUP" "$NAMESPACE/$REDIS_POD:/data/dump.rdb"
    kubectl delete pod "$REDIS_POD" -n "$NAMESPACE"
    kubectl wait --for=condition=ready pod -l app=redis -n "$NAMESPACE" --timeout=300s
    
    print_status "Redis data restored from $LATEST_BACKUP"
}

monitor_redis() {
    echo "🔴 Monitoring Redis commands (Ctrl+C to stop)..."
    REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath="{.items[0].metadata.name}")
    kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli MONITOR
}

flush_redis() {
    echo "🔴 WARNING: This will delete ALL Redis data!"
    read -p "Type 'YES' to confirm: " confirm
    if [ "$confirm" = "YES" ]; then
        REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath="{.items[0].metadata.name}")
        kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli FLUSHALL
        print_status "All Redis data deleted"
    else
        echo "Aborted"
    fi
}

show_keys() {
    local pattern=${2:-"*"}
    echo "🔴 Redis keys matching '$pattern':"
    REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath="{.items[0].metadata.name}")
    kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli KEYS "$pattern"
}

# Main script logic
if [ $# -lt 1 ]; then
    usage
fi

COMMAND=$1
NAMESPACE=${2:-$NAMESPACE}

case $COMMAND in
    backup)
        backup_redis
        ;;
    restore)
        restore_redis
        ;;
    monitor)
        monitor_redis
        ;;
    flush)
        flush_redis
        ;;
    keys)
        show_keys "$@"
        ;;
    *)
        usage
        ;;
esac