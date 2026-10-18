#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Configuration
NAMESPACE=${NAMESPACE:-bacon8}
BACKUP_DIR=${BACKUP_DIR:-./backups}
DB_USER=${DB_USER:-postgres}
DB_NAME=${DB_NAME:-bacon8_prod}
PGPASSWORD=${PGPASSWORD:-postgres}

mkdir -p "$BACKUP_DIR"

usage() {
    echo "Usage: $0 {backup|restore|list|clean|connect|size} [NAMESPACE]"
    echo ""
    echo "Commands:"
    echo "  backup   - Create PostgreSQL backup"
    echo "  restore  - Choose from backup list and restore"  
    echo "  list     - Show all available backups"
    echo "  clean    - Remove old backups (keep newest 10)"
    echo "  connect  - Connect to PostgreSQL shell"
    echo "  size     - Show database sizes"
    echo "  logs     - Show PostgreSQL logs"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 restore"
    echo "  $0 list"
    echo "  $0 connect"
    exit 1
}

get_postgres_pod() {
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    if [ -z "$pod" ]; then
        print_error "No PostgreSQL pod found in namespace $NAMESPACE"
        exit 1
    fi
    echo "$pod"
}

backup_postgres() {
    echo "🐘 Creating PostgreSQL backup..."
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    
    if ! kubectl get deployment -n "$NAMESPACE" postgres &>/dev/null; then
        print_error "PostgreSQL deployment not found in namespace $NAMESPACE"
        exit 1
    fi
    
    POD_NAME=$(get_postgres_pod)
    
    # Create backup
    print_info "Backing up database '$DB_NAME'..."
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" pg_dump -U "$DB_USER" -h db -d "$DB_NAME" > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
    
    # Get backup size
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/db_backup_$TIMESTAMP.sql" | cut -f1)
    print_status "PostgreSQL backup saved: db_backup_$TIMESTAMP.sql ($BACKUP_SIZE)"
}

list_backups() {
    echo "🗃️  Available PostgreSQL backups:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(find "$BACKUP_DIR" -name "db_backup_*.sql" 2>/dev/null)" ]; then
        print_warning "No backup files found in $BACKUP_DIR"
        return
    fi
    
    local counter=1
    ls -lt "$BACKUP_DIR"/db_backup_*.sql | while read -r line; do
        local filename=$(echo "$line" | awk '{print $NF}')
        local basename=$(basename "$filename")
        local size=$(echo "$line" | awk '{print $5}')
        local date=$(echo "$line" | awk '{print $6, $7, $8}')
        
        # Convert size to human readable
        if command -v numfmt >/dev/null 2>&1; then
            size=$(echo "$size" | numfmt --to=iec)
        fi
        
        printf "${BLUE}%2d)${NC} %s ${YELLOW}(%s)${NC} - %s\n" "$counter" "$basename" "$size" "$date"
        counter=$((counter + 1))
    done
}

choose_backup() {
    local backups=($(ls -t "$BACKUP_DIR"/db_backup_*.sql 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "No backup files found in $BACKUP_DIR"
        return 1
    fi
    
    echo ""
    list_backups
    echo ""
    
    while true; do
        echo -n "Enter backup number to restore (1-${#backups[@]}): "
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
            echo "${backups[$((choice-1))]}"
            return 0
        else
            print_error "Invalid choice. Please enter a number between 1 and ${#backups[@]}"
        fi
    done
}

restore_postgres() {
    if [ -z "$(find "$BACKUP_DIR" -name "db_backup_*.sql" 2>/dev/null)" ]; then
        print_error "No PostgreSQL backup files found in $BACKUP_DIR"
        exit 1
    fi
    
    local backup_file
    # Check if first argument (backup file path) was provided
    if [ -n "$1" ]; then
        backup_file="$1"
        if [ ! -f "$backup_file" ]; then
            print_error "Backup file not found: $backup_file"
            exit 1
        fi
    else
        backup_file=$(choose_backup)
        if [ -z "$backup_file" ]; then
            print_error "No backup selected"
            exit 1
        fi
    fi
    
    print_warning "This will COMPLETELY REPLACE the current database!"
    print_info "Database: $DB_NAME"
    print_info "Backup: $(basename "$backup_file")"
    echo ""
    echo -n "Type 'YES' to confirm: "
    read -r confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "Restore cancelled."
        exit 0
    fi
    
    echo "🐘 Restoring PostgreSQL from $(basename "$backup_file")..."
    
    # Get postgres pod
    print_info "Finding PostgreSQL pod..."
    POD_NAME=$(get_postgres_pod)
    print_info "Using pod: $POD_NAME"
    
    # Scale down Bacon8 pods to disconnect from database
    print_info "Scaling down Bacon8 pods to release database connections..."
    if kubectl scale deployment bacon8-web --replicas=0 -n "$NAMESPACE" 2>/dev/null; then
        print_info "Waiting for Bacon8 pods to terminate..."
        kubectl wait --for=delete pod -l app=bacon8-web -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
        sleep 3
    else
        print_warning "Could not scale down Bacon8 pods (they might not exist)"
    fi
    
    # Terminate connections and drop/recreate database
    print_info "Terminating database connections..."
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" psql -U "$DB_USER" -h localhost -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" 2>/dev/null || true
    
    print_info "Dropping existing database..."
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" psql -U "$DB_USER" -h localhost -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null; then
        print_status "Database dropped successfully"
    else
        print_warning "Failed to drop database (it might not exist)"
    fi
    
    print_info "Creating fresh database..."
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" psql -U "$DB_USER" -h localhost -d postgres -c "CREATE DATABASE $DB_NAME;" 2>/dev/null; then
        print_status "Database created successfully"
    else
        print_error "Failed to create database"
        exit 1
    fi
    
    # Import the backup
    print_info "Importing backup data (this may take a while)..."
    if cat "$backup_file" | kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" psql -U "$DB_USER" -h localhost -d "$DB_NAME" -q 2>/dev/null; then
        print_status "Backup data imported successfully"
    else
        print_error "Failed to import backup data"
        exit 1
    fi
    
    # Scale Bacon8 pods back up
    print_info "Scaling Bacon8 pods back up..."
    if kubectl scale deployment bacon8-web --replicas=2 -n "$NAMESPACE" 2>/dev/null; then
        print_info "Waiting for Bacon8 pods to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/bacon8-web -n "$NAMESPACE" 2>/dev/null || true
        print_status "Bacon8 pods are back online"
    else
        print_warning "Could not scale up Bacon8 pods (they might not exist)"
    fi
    
    print_status "Database restored from $(basename "$backup_file")"
    print_info "Restore completed successfully!"
}

clean_backups() {
    echo "🧹 Cleaning old PostgreSQL backups (keeping newest 10)..."
    
    if [ -z "$(find "$BACKUP_DIR" -name "db_backup_*.sql" 2>/dev/null)" ]; then
        print_warning "No backup files found to clean"
        return
    fi
    
    local removed=$(ls -t "$BACKUP_DIR"/db_backup_*.sql 2>/dev/null | tail -n +11 | wc -l)
    ls -t "$BACKUP_DIR"/db_backup_*.sql 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    
    if [ "$removed" -gt 0 ]; then
        print_status "Removed $removed old backup(s)"
    else
        print_info "No old backups to remove"
    fi
}

connect_postgres() {
    echo "🐘 Connecting to PostgreSQL shell..."
    POD_NAME=$(get_postgres_pod)
    print_info "Connected to database '$DB_NAME' in pod '$POD_NAME'"
    print_info "Type 'exit' or Ctrl+D to quit"
    echo ""
    kubectl exec -it -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" psql -U "$DB_USER" -h db -d "$DB_NAME"
}

show_database_sizes() {
    echo "📊 Database sizes:"
    POD_NAME=$(get_postgres_pod)
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env PGPASSWORD="$PGPASSWORD" psql -U "$DB_USER" -h db -d postgres -c "
    SELECT 
        datname as database,
        pg_size_pretty(pg_database_size(datname)) as size
    FROM pg_database 
    WHERE datistemplate = false
    ORDER BY pg_database_size(datname) DESC;"
}

show_logs() {
    echo "📋 PostgreSQL logs (last 50 lines):"
    POD_NAME=$(get_postgres_pod)
    kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=50
}

# Main script logic
if [ $# -lt 1 ]; then
    usage
fi

COMMAND=$1
shift  # Remove the command from arguments

# Set namespace if provided as last argument that looks like a namespace
if [ $# -gt 0 ] && [[ "${!#}" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]] && [[ ! "${!#}" =~ \.sql$ ]]; then
    NAMESPACE="${!#}"
    set -- "${@:1:$(($#-1))}"  # Remove namespace from arguments
fi

case $COMMAND in
    backup)
        backup_postgres
        ;;
    restore)
        restore_postgres "$@"
        ;;
    list)
        list_backups
        ;;
    clean)
        clean_backups
        ;;
    connect)
        connect_postgres
        ;;
    size)
        show_database_sizes
        ;;
    logs)
        show_logs
        ;;
    *)
        usage
        ;;
esac