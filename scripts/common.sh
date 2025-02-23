#!/bin/bash

# Version declaration
JADE_COMMON_VERSION="1.0.0"

# Version management
get_common_version() {
    echo "$JADE_COMMON_VERSION"
}

parse_version() {
    echo "$1" | awk -F. '{ printf("%d%03d%03d\n", $1, $2, $3); }'
}

check_version() {
    local current=$1
    local required=$2
    
    if [ "$(parse_version "$current")" -lt "$(parse_version "$required")" ]; then
        return 1
    fi
    return 0
}

# Export version functions first
export JADE_COMMON_VERSION
export -f parse_version
export -f check_version

# Colors and formatting
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Initialize logging
init_logging() {
    local component=$1
    LOG_FILE="logs/${component}_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$(dirname "$LOG_FILE")"
}

# Enhanced logging functions
log_base() {
    local level=$1
    local msg=$2
    local color=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local script=$(basename "${BASH_SOURCE[2]:-$0}")
    
    # Show message in console
    if [[ "$level" == "ERROR" ]]; then
        # Show detailed error box in console
        echo -e "\n${color}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${color}║                           ERROR                               ║${NC}"
        echo -e "${color}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${color}║ Message: ${msg}${NC}"
        echo -e "${color}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${color}║ Location: ${BASH_SOURCE[2]:-$0}:${BASH_LINENO[1]:-0}${NC}"
        echo -e "${color}║ Command: $BASH_COMMAND${NC}"
        echo -e "${color}║ Working Directory: $(pwd)${NC}"
        echo -e "${color}╚═══════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${color}[${level}]${NC} ${msg}"
    fi
    
    # Write to log file
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] [$script] $msg" >> "$LOG_FILE"
        
        if [[ "$level" == "ERROR" ]]; then
            echo "  → Location: ${BASH_SOURCE[2]:-$0}:${BASH_LINENO[1]:-0}" >> "$LOG_FILE"
            echo "  → Command: $BASH_COMMAND" >> "$LOG_FILE"
            echo "  → Working Directory: $(pwd)" >> "$LOG_FILE"
        fi
    fi
}

log_info() {
    log_base "INFO" "$1" "$BLUE"
}

log_warn() {
    log_base "WARN" "$1" "$YELLOW"
}

log_error() {
    log_base "ERROR" "$1" "$RED"
}

# Basic YAML parsing without yq
parse_yaml() {
    local file=$1
    local key=$2
    
    # Simple YAML parser using grep and sed
    if [[ "$key" == ".requirements.disk_space" ]]; then
        grep "disk_space:" "$file" | sed 's/.*: *//' || echo "5120"
    elif [[ "$key" == ".requirements.memory" ]]; then
        grep "memory:" "$file" | sed 's/.*: *//' || echo "2048"
    elif [[ "$key" == ".packages[].name" ]]; then
        grep "name:" "$file" | sed 's/.*name: *//' | tr -d '"' || echo ""
    elif [[ "$key" == ".docker.network" ]]; then
        grep "network:" "$file" | sed 's/.*: *//' | tr -d '"' || echo "jade-network"
    else
        echo ""
    fi
}

# Configuration functions
load_config() {
    local component=$1
    local config_file="config/${component}.yaml"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    echo "$config_file"
}

get_config_value() {
    local config_file=$1
    local key=$2
    
    # Try using yq if available
    if command -v yq >/dev/null 2>&1; then
        local value
        value=$(yq eval "$key" "$config_file")
        if [ "$value" = "null" ]; then
            log_error "Configuration key not found: $key"
            return 1
        fi
        echo "$value"
        return 0
    fi
    
    # Fallback to basic parsing
    local value
    value=$(parse_yaml "$config_file" "$key")
    if [ -z "$value" ]; then
        log_error "Configuration key not found: $key"
        return 1
    fi
    echo "$value"
    return 0
}

# Deployment status management
get_deployment_status() {
    local component=$1
    local status_file="config/deployment_status.yaml"
    
    if [ ! -f "$status_file" ]; then
        echo "not_deployed"
        return
    fi
    
    # Try using yq if available
    if command -v yq >/dev/null 2>&1; then
        local status
        status=$(yq eval ".$component.status" "$status_file")
        echo "${status:-not_deployed}"
        return
    fi
    
    # Fallback to basic parsing
    local status
    status=$(grep "${component}:" -A1 "$status_file" | grep "status:" | sed 's/.*: *//' | tr -d '"')
    echo "${status:-not_deployed}"
}

update_deployment_status() {
    local component=$1
    local status=$2
    local version=$3
    local status_file="config/deployment_status.yaml"
    
    mkdir -p "$(dirname "$status_file")"
    
    # Create or update status
    if [ ! -f "$status_file" ]; then
        echo "{}" > "$status_file"
    fi
    
    # Try using yq if available
    if command -v yq >/dev/null 2>&1; then
        yq eval -i ".$component = {\"status\": \"$status\", \"version\": \"$version\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" "$status_file"
        return
    fi
    
    # Fallback to basic file manipulation
    local temp_file
    temp_file=$(mktemp)
    {
        echo "---"
        echo "$component:"
        echo "  status: \"$status\""
        echo "  version: \"$version\""
        echo "  timestamp: \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""
    } > "$temp_file"
    mv "$temp_file" "$status_file"
}

# Error handling
setup_error_handling() {
    set -E
    trap 'error_handler $? "${BASH_SOURCE[0]}" ${LINENO} "${BASH_COMMAND}"' ERR
}

error_handler() {
    local exit_code=$1
    local script=$2
    local line_no=$3
    local command=$4
    
    # Show detailed error box in console
    echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                      UNHANDLED ERROR                          ║${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║ Script: $script${NC}"
    echo -e "${RED}║ Line: $line_no${NC}"
    echo -e "${RED}║ Command: $command${NC}"
    echo -e "${RED}║ Exit Code: $exit_code${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║ Working Directory: $(pwd)${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    # Also log to file
    log_error "Unhandled error in script $script line $line_no"
    log_error "Failed command: $command"
    log_error "Exit code: $exit_code"
}

# Deployment status check
check_deployment_status() {
    local status_file="${STATUS_FILE:-/opt/control-panel/.deployment_status}"
    
    if [ -f "$status_file" ]; then
        local last_status=$(cat "$status_file")
        log_info "Found previous deployment status: $last_status"
        return 0
    fi
    return 1
}

# Docker component management
start_docker_component() {
    local component=$1
    local image=$2  # Allow passing pre-expanded image name
    local base_component=${component#jade-}  # Remove 'jade-' prefix if present
    local config_file="config/${base_component}.yaml"
    
    # Get Docker configuration
    if [ -z "$image" ]; then
        image=$(get_config_value "$config_file" ".docker.components[0].image")
    fi
    local network=$(get_config_value "$config_file" ".docker.network")
    
    # Get ports
    local port_args=()
    while IFS= read -r port; do
        port_args+=("-p" "$port")
    done < <(get_config_value "$config_file" ".docker.components[0].ports[]" 2>/dev/null || echo "")
    
    # Get volumes
    local volume_args=()
    while IFS= read -r volume; do
        volume_args+=("-v" "$volume")
    done < <(get_config_value "$config_file" ".docker.components[0].volumes[]" 2>/dev/null || echo "")

    # Get environment variables
    local env_args=()
    while IFS= read -r env; do
        # Replace ${VAR} with actual value from environment
        local expanded_env=$(echo "$env" | envsubst)
        env_args+=("-e" "$expanded_env")
    done < <(get_config_value "$config_file" ".docker.components[0].environment[]" 2>/dev/null || echo "")

    # Only try to pull if image contains a slash (indicating remote registry)
    if [[ "$image" == *"/"* ]]; then
        log_info "Pulling image: $image"
        if ! docker pull "$image" >> "$LOG_FILE" 2>&1; then
            log_error "Failed to pull image: $image"
            return 1
        fi
    fi

    # Start container
    local output
    if ! output=$(docker run -d \
        --name "$component" \
        --restart unless-stopped \
        "${port_args[@]}" \
        --network "$network" \
        "${volume_args[@]}" \
        "${env_args[@]}" \
        "$image" >> "$LOG_FILE" 2>&1); then
        local error_details="Failed to start Docker container\n"
        error_details+="Component: $component\n"
        error_details+="Image: $image\n"
        error_details+="Network: $network\n"
        error_details+="Command output:\n$output"
        log_error "Failed to start Docker container: $component"
        echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                    DOCKER START ERROR                         ║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║ Component: $component${NC}"
        echo -e "${RED}║ Image: $image${NC}"
        echo -e "${RED}║ Network: $network${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║ Error Details:${NC}"
        echo -e "${RED}║ $output${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
    
    return 0
}

stop_docker_component() {
    local component=$1
    
    # Stop and remove container
    local output
    if docker ps -a | grep -q "$component"; then
        if ! output=$(docker stop "$component" 2>&1); then
            local error_details="Failed to stop Docker container\n"
            error_details+="Component: $component\n"
            error_details+="Command output:\n$output"
            log_error "Failed to stop Docker container: $component"
            echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║                    DOCKER STOP ERROR                          ║${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Component: $component${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Error Details:${NC}"
            echo -e "${RED}║ $output${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
            return 1
        fi
        if ! output=$(docker rm "$component" 2>&1); then
            local error_details="Failed to remove Docker container\n"
            error_details+="Component: $component\n"
            error_details+="Command output:\n$output"
            log_error "Failed to remove Docker container: $component"
            echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║                   DOCKER REMOVE ERROR                         ║${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Component: $component${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Error Details:${NC}"
            echo -e "${RED}║ $output${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Testing functions
run_tests() {
    local component=$1
    local type=$2  # deploy or rollback
    local test_script="tests/${component}_${type}_test.sh"
    
    if [ -f "$test_script" ]; then
        local output
        if ! output=$(bash "$test_script" 2>&1); then
            local error_details="Test script execution failed\n"
            error_details+="Component: $component\n"
            error_details+="Test type: $type\n"
            error_details+="Script: $test_script\n"
            error_details+="Command output:\n$output"
            log_error "Test execution failed: $component $type tests"
            echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║                       TEST FAILURE                            ║${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Component: $component${NC}"
            echo -e "${RED}║ Test Type: $type${NC}"
            echo -e "${RED}║ Script: $test_script${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Error Details:${NC}"
            echo -e "${RED}║ $output${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Backup management
create_backup() {
    local component=$1
    local backup_dir=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${backup_dir}/${timestamp}"
    
    # Create backup directory
    local output
    if ! output=$(mkdir -p "$backup_path" 2>&1); then
        local error_details="Failed to create backup directory\n"
        error_details+="Component: $component\n"
        error_details+="Path: $backup_path\n"
        error_details+="Command output:\n$output"
        log_error "Failed to create backup directory: $backup_path"
        echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                     BACKUP ERROR                              ║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║ Component: $component${NC}"
        echo -e "${RED}║ Operation: Create Directory${NC}"
        echo -e "${RED}║ Path: $backup_path${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║ Error Details:${NC}"
        echo -e "${RED}║ $output${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
    
    # Backup configuration files
    if [ -d "config/${component}" ]; then
        if ! output=$(cp -r "config/${component}" "${backup_path}/" 2>&1); then
            local error_details="Failed to backup configuration files\n"
            error_details+="Component: $component\n"
            error_details+="Source: config/${component}\n"
            error_details+="Destination: ${backup_path}/\n"
            error_details+="Command output:\n$output"
            log_error "Failed to backup configuration files: $component"
            echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║                     BACKUP ERROR                              ║${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Component: $component${NC}"
            echo -e "${RED}║ Operation: Copy Config Files${NC}"
            echo -e "${RED}║ Source: config/${component}${NC}"
            echo -e "${RED}║ Destination: ${backup_path}/${NC}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║ Error Details:${NC}"
            echo -e "${RED}║ $output${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
            return 1
        fi
    fi
    
    # Create backup metadata
    if ! output=$(cat > "${backup_path}/metadata.yaml" << EOF
component: ${component}
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: pre_deployment
EOF
2>&1); then
        local error_details="Failed to create backup metadata\n"
        error_details+="Component: $component\n"
        error_details+="Path: ${backup_path}/metadata.yaml\n"
        error_details+="Command output:\n$output"
        log_error "Failed to create backup metadata: $component"
        echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                     BACKUP ERROR                              ║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║ Component: $component${NC}"
        echo -e "${RED}║ Operation: Create Metadata${NC}"
        echo -e "${RED}║ Path: ${backup_path}/metadata.yaml${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║ Error Details:${NC}"
        echo -e "${RED}║ $output${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
    
    return 0
}

# Progress tracking
init_progress() {
    TOTAL_STEPS=$1
    CURRENT_STEP=0
}

update_progress() {
    local message=$1
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -ne "\r[${percentage}%] ${message}..."
}

# Export all functions
export -f init_progress
export -f update_progress
export -f setup_error_handling
export -f error_handler
export -f check_deployment_status
export -f start_docker_component
export -f stop_docker_component
export -f run_tests
export -f create_backup
export -f init_logging
export -f log_base
export -f log_info
export -f log_warn
export -f log_error
export -f load_config
export -f get_config_value
export -f get_deployment_status
export -f update_deployment_status
export -f parse_yaml
