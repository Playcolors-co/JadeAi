#!/bin/bash

# Component information
COMPONENT_NAME="JadeTemplate"
COMPONENT_VERSION="1.0.0"
REQUIRED_VERSION="1.0.0"

# Initialize paths from config
CONFIG_FILE="config/template.yaml"
MESSAGES_FILE="config/messages_template_en.json"

# Source common functions
source "$(dirname "$0")/common.sh"

# Initialize logging
init_logging "template"

# Get message from locale file
get_message() {
    local key=$1
    shift
    local value
    value=$(jq -r ".$key" "$MESSAGES_FILE" 2>/dev/null)
    if [ "$value" = "null" ]; then
        echo "Message not found: $key"
    else
        # Replace parameters
        local i=0
        for param in "$@"; do
            value=${value//\{$i\}/$param}
            i=$((i + 1))
        done
        echo "$value"
    fi
}

# Load paths from config
load_paths() {
    local output
    if ! output=$(yq eval '.deployment.backup_dir' "$CONFIG_FILE" 2>&1); then
        local error_details="Failed to read backup directory from config\n"
        error_details+="Config file: $CONFIG_FILE\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to load configuration" "$error_details" true
        return 1
    fi
    BACKUP_DIR="$output"

    if ! output=$(yq eval '.deployment.status_file' "$CONFIG_FILE" 2>&1); then
        local error_details="Failed to read status file from config\n"
        error_details+="Config file: $CONFIG_FILE\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to load configuration" "$error_details" true
        return 1
    fi
    STATUS_FILE="$output"

    if ! output=$(yq eval '.deployment.log_dir' "$CONFIG_FILE" 2>&1); then
        local error_details="Failed to read log directory from config\n"
        error_details+="Config file: $CONFIG_FILE\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to load configuration" "$error_details" true
        return 1
    fi
    LOG_DIR="$output"
    
    # Create directories if they don't exist
    if ! output=$(mkdir -p "$BACKUP_DIR" "$LOG_DIR" 2>&1); then
        local error_details="Failed to create required directories\n"
        error_details+="Backup directory: $BACKUP_DIR\n"
        error_details+="Log directory: $LOG_DIR\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to create directories" "$error_details" true
        return 1
    fi
}

# Error handling with enhanced details and execution control
handle_error() {
    local error_msg=$1
    local command_output=$2
    local is_critical=${3:-true}  # Default to critical error
    
    # Format error details
    local error_details="Error: $error_msg\n"
    error_details+="Command output:\n$command_output\n"
    error_details+="Stack trace:\n"
    error_details+="  File: ${BASH_SOURCE[1]}\n"
    error_details+="  Line: ${BASH_LINENO[0]}\n"
    error_details+="  Command: $BASH_COMMAND\n"
    error_details+="  Working Directory: $(pwd)"
    
    # Log full error details
    echo -e "$error_details" >> "$LOG_FILE"
    
    # Show detailed error in console with high visibility
    echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                           ERROR                               ║${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║ Message: $error_msg${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║ Details:${NC}"
    echo -e "${RED}║ $command_output${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║ Location: ${BASH_SOURCE[1]}:${BASH_LINENO[0]}${NC}"
    echo -e "${RED}║ Command: $BASH_COMMAND${NC}"
    echo -e "${RED}║ Working Directory: $(pwd)${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    # For critical errors, exit the script
    if [ "$is_critical" = true ]; then
        log_error "Critical error occurred. Stopping deployment..."
        exit 1
    fi
    
    return 1
}

# Check prerequisites
check_prerequisites() {
    log_info "$(get_message "template.info.prerequisites.checking")"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        local error_details="Current user is not root\n"
        error_details+="User ID: $EUID\n"
        error_details+="Please run this script with sudo or as root user."
        handle_error "$(get_message "template.error.root_required")" "$error_details" true
        return 1
    fi
    
    # Check system setup
    if [ ! -f "/opt/control-panel/.system_setup_complete" ]; then
        local error_details="System setup marker not found\n"
        error_details+="Expected file: /opt/control-panel/.system_setup_complete\n"
        error_details+="Please complete system setup first."
        handle_error "$(get_message "template.error.system_setup")" "$error_details" true
        return 1
    fi
    
    # Check system requirements
    local output
    local required_memory required_disk
    
    if ! required_memory=$(yq eval '.requirements.memory' "$CONFIG_FILE" 2>&1); then
        local error_details="Failed to read memory requirement from config\n"
        error_details+="Config file: $CONFIG_FILE\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to read configuration" "$error_details" true
        return 1
    fi
    
    if ! required_disk=$(yq eval '.requirements.disk_space' "$CONFIG_FILE" 2>&1); then
        local error_details="Failed to read disk space requirement from config\n"
        error_details+="Config file: $CONFIG_FILE\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to read configuration" "$error_details" true
        return 1
    fi
    
    local available_memory=$(free -m | awk '/Mem:/ {print $2}')
    local available_disk=$(df -m /opt/control-panel 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        local error_details="Insufficient memory available\n"
        error_details+="Available: ${available_memory}MB\n"
        error_details+="Required: ${required_memory}MB"
        handle_error "$(get_message "template.info.system.memory_warning" "$available_memory" "$required_memory")" "$error_details" true
        return 1
    fi
    
    if [ "$available_disk" -lt "$required_disk" ]; then
        local error_details="Insufficient disk space available\n"
        error_details+="Available: ${available_disk}MB\n"
        error_details+="Required: ${required_disk}MB"
        handle_error "$(get_message "template.info.system.disk_warning" "$available_disk" "$required_disk")" "$error_details" true
        return 1
    fi
    
    log_info "$(get_message "template.info.prerequisites.passed")"
    return 0
}

# Backup function
backup_component() {
    log_info "$(get_message "template.info.backup.start")"
    
    # Get backup directory from config
    local backup_dir=$(yq eval '.deployment.backup_dir' "$CONFIG_FILE")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${backup_dir}/${timestamp}"
    
    local output
    if ! output=$(mkdir -p "$backup_path" 2>&1); then
        local error_details="Failed to create backup directory\n"
        error_details+="Path: $backup_path\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to create backup directory" "$error_details" true
        return 1
    fi
    
    # Add component-specific backup commands here
    # Example:
    # if [ -d "/etc/component" ]; then
    #     if ! output=$(cp -r "/etc/component" "${backup_path}/" 2>&1); then
    #         local error_details="Failed to backup component files\n"
    #         error_details+="Source: /etc/component\n"
    #         error_details+="Destination: ${backup_path}/\n"
    #         error_details+="Command output:\n$output"
    #         handle_error "Failed to backup component configuration" "$error_details" true
    #         return 1
    #     fi
    # fi
    
    # Create backup metadata
    if ! output=$(cat > "${backup_path}/metadata.yaml" << EOF
version: ${COMPONENT_VERSION}
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
component: ${COMPONENT_NAME}
config_file: ${CONFIG_FILE}
EOF
2>&1); then
        local error_details="Failed to create backup metadata file\n"
        error_details+="Path: ${backup_path}/metadata.yaml\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to create backup metadata" "$error_details" true
        return 1
    fi
    
    log_info "$(get_message "template.info.backup.complete" "${backup_path}")"
    return 0
}

# Rollback function
rollback_component() {
    log_info "$(get_message "template.info.rollback.start")"
    
    # Find latest backup
    local backup_dir=$(yq eval '.deployment.backup_dir' "$CONFIG_FILE")
    local latest_backup=$(ls -td ${backup_dir}/*/ 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        local error_details="No backup directory found in: $backup_dir\n"
        error_details+="Expected backup directory structure: $backup_dir/YYYYMMDD_HHMMSS/\n"
        error_details+="Please ensure a backup exists before attempting rollback."
        handle_error "$(get_message "template.error.no_backup")" "$error_details" true
        return 1
    fi
    
    local output
    # Add component-specific rollback commands here
    # Example:
    # if [ -d "${latest_backup}/component" ]; then
    #     if ! output=$(sudo cp -r "${latest_backup}/component" "/etc/" 2>&1); then
    #         local error_details="Failed to restore component files\n"
    #         error_details+="Source: ${latest_backup}/component\n"
    #         error_details+="Destination: /etc/\n"
    #         error_details+="Command output:\n$output"
    #         handle_error "Failed to restore component configuration" "$error_details" true
    #         return 1
    #     fi
    # fi
    
    log_info "$(get_message "template.info.rollback.complete")"
    return 0
}

# Test function
test_component() {
    log_info "$(get_message "template.info.testing")"
    
    local output
    # Add component-specific test commands here
    # Example:
    # if ! output=$(systemctl is-active --quiet component 2>&1); then
    #     local error_details="Component service is not running\n"
    #     error_details+="Service status:\n$(systemctl status component 2>&1)"
    #     handle_error "$(get_message "template.error.service.not_running")" "$error_details" true
    #     return 1
    # fi
    
    log_info "$(get_message "template.info.tests_passed")"
    return 0
}

# Main setup function
setup_component() {
    log_info "$(get_message "template.info.setup_start")"
    
    # Load paths from config
    load_paths
    
    # Check version compatibility
    log_info "Checking version compatibility..."
    if ! check_version "$COMPONENT_VERSION" "$REQUIRED_VERSION"; then
        local error_details="Current version: $COMPONENT_VERSION\n"
        error_details+="Required version: $REQUIRED_VERSION\n"
        error_details+="Please update the component to the required version."
        handle_error "Version compatibility check failed" "$error_details" true
        return 1
    fi
    
    # Check deployment status and create backup if needed
    log_info "Checking deployment status..."
    if check_deployment_status; then
        log_warn "Previous deployment found. Creating backup before proceeding..."
        if ! backup_component; then
            local error_details="Failed to create backup before deployment\n"
            error_details+="Please check the logs for backup failure details."
            handle_error "$(get_message "template.error.backup_failed")" "$error_details" true
            return 1
        fi
    fi
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Add component-specific setup commands here
    # Example:
    # log_info "$(get_message "template.info.installing")"
    # if ! output=$(DEBIAN_FRONTEND=noninteractive sudo apt-get install -y package-name 2>&1); then
    #     local error_details="Failed to install required package\n"
    #     error_details+="Package: package-name\n"
    #     error_details+="Command output:\n$output"
    #     handle_error "$(get_message "template.error.package_install" "package-name")" "$error_details" true
    #     return 1
    # fi
    
    # Create setup completion marker
    local output
    if ! output=$(echo "$COMPONENT_VERSION" > "$STATUS_FILE" 2>&1); then
        local error_details="Failed to write version to status file\n"
        error_details+="Status file: $STATUS_FILE\n"
        error_details+="Version: $COMPONENT_VERSION\n"
        error_details+="Command output:\n$output"
        handle_error "$(get_message "template.error.marker_create")" "$error_details" true
        return 1
    fi
    
    # Test the setup
    if ! test_component; then
        local error_details="Component verification tests failed\n"
        error_details+="Please check the test logs for specific failures\n"
        error_details+="Running rollback to restore previous state..."
        handle_error "$(get_message "template.error.setup_verify")" "$error_details" true
        rollback_component
        return 1
    fi
    
    log_info "$(get_message "template.info.setup_complete")"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set up error handling
    setup_error_handling
    
    # Run setup
    if ! setup_component; then
        local error_details="Template component deployment failed\n"
        error_details+="Please check the logs at $LOG_FILE for detailed error information.\n"
        error_details+="You may need to run rollback to clean up any partial deployment."
        handle_error "Failed to deploy template component" "$error_details" true
        exit 1
    fi
fi
