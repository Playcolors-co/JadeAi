#!/bin/bash

# Source common functions
source "$(dirname "$0")/common.sh"

# Component information
COMPONENT_NAME="system"
COMPONENT_VERSION="1.0.0"
REQUIRED_VERSION="1.0.0"
BACKUP_DIR="/opt/control-panel/backups/${COMPONENT_NAME}"
CONFIG_FILE="/opt/control-panel/config/${COMPONENT_NAME}.yaml"
STATUS_FILE="/opt/control-panel/.${COMPONENT_NAME}_setup_complete"

# Initialize logging
init_logging "$COMPONENT_NAME"

# Configure package repositories
configure_repositories() {
    log_info "Configuring package repositories..."
    
    # Remove any existing Docker repository file that might be malformed
    sudo rm -f /etc/apt/sources.list.d/docker.list
    
    # Configure apt sources
    local sources_list="/etc/apt/sources.list"
    
    # Backup original sources.list
    sudo cp "$sources_list" "${sources_list}.backup"
    
    # Create new sources.list
    {
        echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware"
        echo "deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware"
        echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware"
    } | sudo tee "$sources_list" > /dev/null
    
    # Add Raspberry Pi repository
    if [ ! -f /etc/apt/sources.list.d/raspi.list ]; then
        echo "deb http://archive.raspberrypi.com/debian/ bookworm main" | \
            sudo tee /etc/apt/sources.list.d/raspi.list > /dev/null
    fi
    
    # Test connectivity
    if curl -s -m 5 "http://deb.debian.org/debian/dists/bookworm/Release" >/dev/null 2>&1; then
        log_info "Repository configuration successful"
        return 0
    fi
    
    # Restore original configuration if failed
    [ -f "${sources_list}.backup" ] && sudo mv "${sources_list}.backup" "$sources_list"
    
    log_error "Repository configuration failed"
    return 1
}

# Test network connectivity
test_network() {
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s -m 5 "http://deb.debian.org/debian/dists/bookworm/Release" >/dev/null 2>&1; then
            log_info "Network connectivity test passed"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warn "Network test failed, retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    log_error "Network connectivity test failed"
    return 1
}

# Install common libraries
install_common_libraries() {
    log_info "Installing common libraries..."
    
    # Update package lists
    if ! DEBIAN_FRONTEND=noninteractive sudo apt-get update >> "$LOG_FILE" 2>&1; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Read required packages from config
    local packages=$(yq eval '.required_packages[]' "$CONFIG_FILE" | tr '\n' ' ')
    
    # Install each package with retry
    for pkg in $packages; do
        local retry_count=0
        local max_retries=3
        
        while [ $retry_count -lt $max_retries ]; do
            log_info "Installing package: $pkg"
            if DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1; then
                break
            fi
            
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warn "Retry attempt $retry_count of $max_retries"
                sleep 5
            else
                log_error "Failed to install package: $pkg"
                return 1
            fi
        done
    done
    
    log_info "Common libraries installation complete"
    return 0
}

# Create required directories
create_directories() {
    log_info "Creating required directories..."
    
    # Read required directories from config
    local dirs=$(yq eval '.required_dirs[]' "$CONFIG_FILE" | tr '\n' ' ')
    local mode="755"
    
    # Create each directory
    for dir in $dirs; do
        if ! sudo mkdir -p "$dir"; then
            log_error "Failed to create directory: $dir"
            return 1
        fi
        
        if ! sudo chmod "$mode" "$dir"; then
            log_error "Failed to set permissions for directory: $dir"
            return 1
        fi
    done
    
    log_info "Directory creation complete"
    return 0
}

# Test system setup
test_component() {
    log_info "Testing system setup..."
    
    # Check required directories
    local dirs=$(yq eval '.required_dirs[]' "$CONFIG_FILE" | tr '\n' ' ')
    for dir in $dirs; do
        if [ ! -d "$dir" ]; then
            log_error "Required directory not found: $dir"
            return 1
        fi
    done
    
    # Check required packages
    local packages=$(yq eval '.required_packages[]' "$CONFIG_FILE" | tr '\n' ' ')
    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_error "Required package not installed: $pkg"
            return 1
        fi
    done
    
    # Check Python version
    local required_python_version=$(yq eval '.required_python_version' "$CONFIG_FILE")
    local current_python_version=$(python3 --version | cut -d' ' -f2)
    if ! check_version "$current_python_version" "$required_python_version"; then
        log_error "Python version check failed"
        return 1
    fi
    
    log_info "System tests passed successfully"
    return 0
}

# Rollback function
rollback_component() {
    log_info "Rolling back ${COMPONENT_NAME}..."
    
    # Find latest backup
    local latest_backup=$(ls -td ${BACKUP_DIR}/*/ 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup found for rollback"
        return 1
    fi
    
    # Restore configuration
    if [ -f "${latest_backup}/config/$(basename "$CONFIG_FILE")" ]; then
        cp "${latest_backup}/config/$(basename "$CONFIG_FILE")" "$CONFIG_FILE"
    fi
    
    # Restore sources.list if backup exists
    if [ -f "/etc/apt/sources.list.backup" ]; then
        sudo mv "/etc/apt/sources.list.backup" "/etc/apt/sources.list"
    fi
    
    log_info "Rollback completed successfully"
    return 0
}

# Backup function
backup_component() {
    log_info "Creating backup of ${COMPONENT_NAME}..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Get timestamp for backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/${timestamp}"
    
    # Backup configuration and data
    if [ -f "$CONFIG_FILE" ]; then
        mkdir -p "${backup_path}/config"
        cp "$CONFIG_FILE" "${backup_path}/config/"
    fi
    
    # Create backup metadata
    cat > "${backup_path}/metadata.yaml" << EOF
version: ${COMPONENT_VERSION}
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
component: ${COMPONENT_NAME}
config_file: ${CONFIG_FILE}
EOF
    
    log_info "Backup created at: ${backup_path}"
    return 0
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi

    # Install yq if not present
    if ! command -v yq >/dev/null 2>&1; then
        log_info "Installing yq..."
        if ! wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64; then
            log_error "Failed to download yq"
            return 1
        fi
        chmod +x /usr/local/bin/yq
    fi
    
    # Check disk space
    local required_space=$(yq eval '.disk_space.required' "$CONFIG_FILE")
    local available_space
    available_space=$(df -k /opt | awk 'NR==2 {print $4}')
    if [ -n "$available_space" ] && [ "$available_space" -lt "$required_space" ]; then
        log_error "Insufficient disk space. Required: ${required_space}KB, Available: ${available_space}KB"
        return 1
    fi
    
    # Check network connectivity
    if ! test_network; then
        return 1
    fi
    
    log_info "Prerequisites check passed"
    return 0
}

# Main setup function
setup_component() {
    log_info "Starting system setup..."
    
    # Check version compatibility
    log_info "Checking version compatibility..."
    if ! check_version "$COMPONENT_VERSION" "$REQUIRED_VERSION"; then
        return 1
    fi
    
    # Check deployment status and create backup if needed
    log_info "Checking deployment status..."
    if check_deployment_status; then
        log_warn "Previous deployment found. Creating backup before proceeding..."
        if ! backup_component; then
            log_error "Backup failed, aborting deployment"
            return 1
        fi
    fi
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Configure repositories
    if ! configure_repositories; then
        return 1
    fi
    
    # Install common libraries
    if ! install_common_libraries; then
        return 1
    fi
    
    # Create required directories
    if ! create_directories; then
        return 1
    fi
    
    # Create setup completion marker
    echo "$COMPONENT_VERSION" > "$STATUS_FILE"
    if [ $? -ne 0 ]; then
        log_error "Failed to create setup completion marker"
        return 1
    fi
    
    # Test the setup
    if ! test_component; then
        log_error "System setup verification failed"
        rollback_component
        return 1
    fi
    
    log_info "System setup completed successfully"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set up error handling
    setup_error_handling
    
    # Run setup
    if ! setup_component; then
        exit 1
    fi
fi
