#!/bin/bash

# Jade AI Deployment Script
REMOTE_HOST="192.168.88.59"
REMOTE_USER="root"
REMOTE_PASS="password"
REMOTE_DIR="/opt/jadeai"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$LOCAL_DIR/logs/deploy_$(date +%Y%m%d_%H%M%S).log"
MESSAGES_FILE="$LOCAL_DIR/config/messages_deploy_en.json"

# Maximum retries for operations
MAX_RETRIES=3
RETRY_DELAY=5

# Colors and formatting
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Get message from JSON file
get_message() {
    local type=$1
    local key=$2
    local params=("${@:3}")
    
    # Get message template
    local message=$(jq -r ".deploy.$type.$key" "$MESSAGES_FILE")
    
    # Replace parameters
    for i in "${!params[@]}"; do
        message=${message//\{$i\}/${params[$i]}}
    done
    
    echo "$message"
}

# Logging functions
log_info() {
    local key=$1
    shift
    local message=$(get_message "info" "$key" "$@")
    echo -e "${BLUE}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
}

log_warn() {
    local key=$1
    shift
    local message=$(get_message "warn" "$key" "$@")
    echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
}

log_error() {
    local key=$1
    shift
    local message=$(get_message "error" "$key" "$@")
    echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log_info "prerequisites"
    
    # Install jq if not present (needed for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        echo "Installing jq..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if ! brew install jq; then
                echo "Failed to install jq"
                return 1
            fi
        else
            if ! sudo apt-get update && sudo apt-get install -y jq; then
                echo "Failed to install jq"
                return 1
            fi
        fi
    fi
    
    # Check if rsync is installed
    if ! command -v rsync >/dev/null 2>&1; then
        log_error "rsync_missing"
        return 1
    fi
    
    # Check if ssh is installed
    if ! command -v ssh >/dev/null 2>&1; then
        log_error "ssh_missing"
        return 1
    fi
    
    # Check if ssh-keygen is installed
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log_error "keygen_missing"
        return 1
    fi
    
    # Check if sshpass is installed when password is provided
    if [ -n "$REMOTE_PASS" ] && ! command -v sshpass >/dev/null 2>&1; then
        log_info "prerequisites" "Installing sshpass..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if ! brew install hudochenkov/sshpass/sshpass; then
                log_error "prerequisites" "Failed to install sshpass"
                return 1
            fi
        else
            if ! sudo apt-get update && sudo apt-get install -y sshpass; then
                log_error "prerequisites" "Failed to install sshpass"
                return 1
            fi
        fi
    fi
    
    # Check if remote host is reachable
    if ! ping -c 1 "$REMOTE_HOST" >/dev/null 2>&1; then
        log_error "host_unreachable" "$REMOTE_HOST"
        return 1
    fi
    
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    return 0
}

# Function to set up SSH authentication
setup_ssh() {
    log_info "ssh_setup"
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Create SSH key if it doesn't exist
        if [ ! -f ~/.ssh/id_rsa ]; then
            log_info "ssh_setup" "Generating SSH key..."
            if ! ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa; then
                log_error "ssh_auth"
                return 1
            fi
        else
            log_warn "ssh_key_exists"
        fi
        
        # Copy SSH key using password if provided
        if [ -n "$REMOTE_PASS" ]; then
            if sshpass -p "$REMOTE_PASS" ssh-copy-id -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST"; then
                log_info "ssh_success"
                return 0
            fi
        else
            # Try key-based authentication
            if ssh-copy-id -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST"; then
                log_info "ssh_success"
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            log_warn "retry_attempt" "$retry_count" "$MAX_RETRIES"
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "ssh_auth"
    return 1
}

# Function to copy files to remote host
copy_files() {
    log_info "files_copy"
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Create remote directories with sudo
        if [ -n "$REMOTE_PASS" ]; then
            if sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "echo '$REMOTE_PASS' | sudo -S mkdir -p $REMOTE_DIR /opt/control-panel/config /opt/control-panel/logs /opt/control-panel/backups && echo '$REMOTE_PASS' | sudo -S chown -R $REMOTE_USER:$REMOTE_USER $REMOTE_DIR /opt/control-panel"; then
                # Copy all files
                if rsync -az --quiet \
                    --exclude '.git' \
                    --exclude '.DS_Store' \
                    --exclude 'node_modules' \
                    --exclude '*.log' \
                    "$LOCAL_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"; then
                    
                    # Copy config files to control panel directory
                    if rsync -az --quiet "$LOCAL_DIR/config/" "$REMOTE_USER@$REMOTE_HOST:/opt/control-panel/config/"; then
                        # Set permissions
                        if sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "echo '$REMOTE_PASS' | sudo -S chmod -R 755 $REMOTE_DIR/scripts/*.sh $REMOTE_DIR/tests/*.sh"; then
                            log_info "files_success"
                            return 0
                        fi
                    fi
                fi
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            log_warn "retry_attempt" "$retry_count" "$MAX_RETRIES"
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "files_copy" "Maximum retries reached"
    return 1
}

# Function to execute remote deployment
execute_deployment() {
    log_info "deployment_start"
    
    # Array of components in deployment order
    local components=(
        "system"
        "docker"
        "portainer"
        "video"
        "hid"
        "bluetooth"
        "wifi"
        "web_admin"
    )
    
    # Deploy each component
    for component in "${components[@]}"; do
        log_info "component_deploy" "$component"
        
        local retry_count=0
        local success=false
        local output=""
        local temp_log=$(mktemp)
        
        while [ $retry_count -lt $MAX_RETRIES ]; do
            # Execute component setup script and capture both exit code and output
            if [ -n "$REMOTE_PASS" ]; then
                # Execute with password
                sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && echo '$REMOTE_PASS' | sudo -E -S bash ./scripts/${component}_setup.sh" 2>&1 | tee "$temp_log"
                exit_code=${PIPESTATUS[0]}
            else
                # Execute without password
                ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && sudo -E bash ./scripts/${component}_setup.sh" 2>&1 | tee "$temp_log"
                exit_code=${PIPESTATUS[0]}
            fi

            # Check if component succeeded
            if [ $exit_code -eq 0 ]; then
                log_info "component_success" "$component"
                success=true
                break
            fi
            
            # If component failed, check if it's a critical error
            if grep -q "╔═.*ERROR.*═╗" "$temp_log"; then
                # Found error box, display it and stop deployment
                log_error "component_deploy" "$component"
                echo -e "\n${RED}Deployment stopped due to critical error in $component component${NC}"
                echo -e "${RED}Error details:${NC}"
                # Extract and display the error box
                awk '/╔═.*ERROR.*═╗/,/╚═.*═╝/' "$temp_log"
                rm -f "$temp_log"
                return 1
            fi
            
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $MAX_RETRIES ]; then
                log_warn "retry_attempt" "$retry_count" "$MAX_RETRIES"
                sleep $RETRY_DELAY
            fi
        done
        
        if ! $success; then
            log_error "component_deploy" "$component"
            echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║                  COMPONENT DEPLOYMENT ERROR                    ║${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Component: $component${NC}"
            echo -e "${RED}║ Status: Failed after $retry_count attempts${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Error Details:${NC}"
            echo -e "${RED}║ $(cat "$temp_log")${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
            rm -f "$temp_log"
            return 1
        fi
        
        rm -f "$temp_log"
    done
    
    return 0
}

# Main execution
main() {
    log_info "start" "$REMOTE_HOST"
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "prerequisites"
        return 1
    fi
    
    # Setup SSH authentication
    if ! setup_ssh; then
        return 1
    fi
    
    # Copy files to remote host
    if ! copy_files; then
        return 1
    fi
    
    # Execute deployment
    if ! execute_deployment; then
        return 1
    fi
    
    log_info "complete"
    log_info "web_access" "$REMOTE_HOST"
    log_info "portainer_access" "$REMOTE_HOST"
    log_info "log_location" "$LOG_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --user)
            REMOTE_USER="$2"
            shift 2
            ;;
        --pass)
            REMOTE_PASS="$2"
            shift 2
            ;;
        --dir)
            REMOTE_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --host HOST    Remote host (default: 192.168.88.59)"
            echo "  --user USER    Remote username (default: theboxpi)"
            echo "  --pass PASS    Remote password (optional)"
            echo "  --dir DIR      Remote directory (default: /opt/jadeai)"
            echo "  --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main
