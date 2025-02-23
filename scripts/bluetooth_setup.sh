#!/bin/bash

# Version declaration
JADE_BLUETOOTH_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"
REQUIRED_SYSTEM_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize logging
init_logging "bluetooth"

# Load messages file
MESSAGES_FILE="config/messages_bluetooth_en.json"

# Get message from locale file
get_message() {
    local key=$1
    shift
    local value
    value=$(jq -r ".bluetooth.$key" "$MESSAGES_FILE" 2>/dev/null)
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

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    log_error "$(get_message "error.prerequisites.version" "$REQUIRED_COMMON_VERSION" "$JADE_COMMON_VERSION")"
    exit 1
fi

# Load configuration
CONFIG_FILE=$(load_config "bluetooth")
if [ $? -ne 0 ]; then
    log_error "$(get_message "error.config.load")"
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "prerequisites.checking"
    
    # Check if system component is deployed
    if [ ! -f "/opt/control-panel/.system_setup_complete" ]; then
        log_error "prerequisites.system"
        return 1
    fi
    
    # Check system version
    local system_version=$(get_config_value "$(load_config "system")" ".version")
    if ! check_version "$system_version" "$REQUIRED_SYSTEM_VERSION"; then
        log_error "prerequisites.version" "$REQUIRED_SYSTEM_VERSION" "$system_version"
        return 1
    fi
    
    # Check hardware
    if ! check_hardware; then
        return 1
    fi
    
    log_info "prerequisites.passed"
    return 0
}

# Function to check hardware
check_hardware() {
    log_info "$(get_message "info.hardware.checking")"
    
    local max_retries=3
    local retry_count=0
    local success=false
    
    while [ $retry_count -lt $max_retries ]; do
        # Try to start bluetooth service
        systemctl start bluetooth || true
        sleep 2
        
        # Check adapter
        if hciconfig 2>/dev/null | grep -q "hci"; then
            # Found adapter, now check if it's usable
            if hciconfig -a 2>/dev/null | grep -q "BR/EDR"; then
                # Check if blocked
                if ! rfkill list bluetooth 2>/dev/null | grep -q "blocked: yes"; then
                    # Try to initialize
                    if hciconfig hci0 up 2>/dev/null; then
                        success=true
                        break
                    fi
                else
                    log_info "$(get_message "info.hardware.unblocking")"
                    rfkill unblock bluetooth
                    sleep 2
                    continue
                fi
            fi
        fi
        
        log_warn "$(get_message "warn.retry" "$((retry_count + 1))" "$max_retries")"
        retry_count=$((retry_count + 1))
        sleep 5
    done
    
    if [ "$success" = false ]; then
        log_error "$(get_message "error.hardware.not_found")"
        return 1
    fi
    
    return 0
}

# Function to create required directories
create_directories() {
    log_info "$(get_message "info.directories.creating")"
    
    # Get directories from config
    local directories=($(get_config_value "$CONFIG_FILE" ".directories[].path"))
    local modes=($(get_config_value "$CONFIG_FILE" ".directories[].mode"))
    
    # Create each directory with proper permissions
    local i=0
    for dir in "${directories[@]}"; do
        sudo mkdir -p "$dir"
        sudo chmod "${modes[$i]}" "$dir"
        ((i++))
    done
    
    log_info "$(get_message "info.directories.complete")"
    return 0
}

# Function to install required packages
install_packages() {
    log_info "$(get_message "info.packages.installing")"
    
    # Update package lists
    if ! DEBIAN_FRONTEND=noninteractive sudo apt-get update >> "$LOG_FILE" 2>&1; then
        log_error "package.update_failed"
        return 1
    fi
    
    # Get required packages from config
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    
    # Install each package
    for pkg in "${packages[@]}"; do
        log_info "$(get_message "info.packages.installing_specific" "$pkg")"
        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1; then
            log_error "package.install" "$pkg"
            return 1
        fi
    done
    
    log_info "$(get_message "info.packages.complete")"
    return 0
}

# Function to configure bluetooth service
configure_service() {
    log_info "$(get_message "info.service.configuring")"
    
    local config_file=$(get_config_value "$CONFIG_FILE" ".service.config_file")
    local service_name=$(get_config_value "$CONFIG_FILE" ".service.name")
    local systemd_unit=$(get_config_value "$CONFIG_FILE" ".service.systemd_unit")
    
    # Create backup if enabled
    if [ "$(get_config_value "$CONFIG_FILE" ".deployment.backup.enabled")" = "true" ]; then
        local backup_dir=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        local backup_file="${backup_dir}/$(basename "$config_file").$(date +%Y%m%d_%H%M%S)"
        
        if [ -f "$config_file" ]; then
            sudo mkdir -p "$backup_dir"
            if ! sudo cp "$config_file" "$backup_file"; then
                log_warn "backup.partial"
            fi
        else
            log_warn "backup.skipped"
        fi
    fi
    
    # Configure bluetooth service
    sudo mkdir -p "$(dirname "$config_file")"
    {
        echo "[General]"
        echo "Name = $(get_config_value "$CONFIG_FILE" ".service.display_name")"
        echo "DiscoverableTimeout = $(get_config_value "$CONFIG_FILE" ".service.discoverable_timeout")"
        echo "Discoverable = $(get_config_value "$CONFIG_FILE" ".service.discoverable")"
        echo "[Policy]"
        echo "AutoEnable = $(get_config_value "$CONFIG_FILE" ".service.auto_enable")"
    } | sudo tee "$config_file" > /dev/null
    
    if [ $? -ne 0 ]; then
        log_error "service.config"
        return 1
    fi
    
    # Restart bluetooth service
    log_info "$(get_message "info.service.starting")"
    if ! sudo systemctl restart "$systemd_unit"; then
        log_error "service.start"
        return 1
    fi
    
    # Check if service is running
    if ! systemctl is-active --quiet "$systemd_unit"; then
        log_error "service.status"
        return 1
    fi
    
    # Check D-Bus connection
    if ! dbus-send --system --dest=org.bluez / org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1; then
        log_error "service.dbus"
        return 1
    fi
    
    log_info "$(get_message "info.service.complete")"
    return 0
}

# Function to setup Docker container
setup_docker() {
    log_info "$(get_message "info.docker.setup")"
    
    local network=$(get_config_value "$CONFIG_FILE" ".docker.network")
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    local compose_file=$(get_config_value "$CONFIG_FILE" ".docker.compose_file")
    
    # Ensure network exists
    if ! docker network inspect "$network" >/dev/null 2>&1; then
        if ! docker network create "$network"; then
            log_error "docker.network"
            return 1
        fi
    fi
    
    # Check if docker-compose file exists and use it
    if [ -f "$compose_file" ]; then
        log_info "$(get_message "info.docker.compose")"
        export JADE_BLUETOOTH_VERSION
        if ! docker-compose -f "$compose_file" up -d; then
            log_error "docker.compose_failed"
            return 1
        fi
        unset JADE_BLUETOOTH_VERSION
    else
        # Build Docker image
        log_info "$(get_message "info.docker.building")"
        if ! docker build -t "${component}:${JADE_BLUETOOTH_VERSION}" -f Dockerfile.bluetooth . >> "$LOG_FILE" 2>&1; then
            log_error "docker.build"
            return 1
        fi
        
        # Check if container exists and remove it
        if docker ps -a | grep -q "$component"; then
            if ! docker rm -f "$component" >> "$LOG_FILE" 2>&1; then
                log_error "docker.remove"
                return 1
            fi
        fi
        
        # Start container with config settings
        log_info "$(get_message "info.docker.starting")"
        
        # Create docker run command with settings from yaml
        local docker_cmd="docker run -d --name $component"
        docker_cmd+=" --network=$network"
        docker_cmd+=" --privileged"
        docker_cmd+=" --network=host"
        
        # Add volumes
        local volumes=($(get_config_value "$CONFIG_FILE" ".docker.components[0].volumes[]"))
        for volume in "${volumes[@]}"; do
            docker_cmd+=" -v $volume"
        done
        
        # Add environment variables
        local env_vars=($(get_config_value "$CONFIG_FILE" ".docker.components[0].environment[]"))
        for env_var in "${env_vars[@]}"; do
            docker_cmd+=" -e $env_var"
        done
        
        docker_cmd+=" ${component}:${JADE_BLUETOOTH_VERSION}"
        
        if ! eval "$docker_cmd" >> "$LOG_FILE" 2>&1; then
            log_error "docker.start"
            return 1
        fi
    fi
    
    # Verify container is running
    if ! docker ps | grep -q "$component"; then
        log_error "docker.verify"
        return 1
    fi
    
    log_info "$(get_message "info.docker.complete")"
    return 0
}

# Function to test bluetooth setup
test_bluetooth() {
    log_info "$(get_message "info.testing")"
    
    # Check if bluetooth service is running
    if ! systemctl is-active --quiet bluetooth; then
        log_error "test.service"
        return 1
    fi
    
    # Check if bluetooth adapter is powered on and can detect devices
    if ! hciconfig hci0 up 2>/dev/null; then
        log_error "test.adapter"
        return 1
    fi
    
    # Test scanning functionality
    if ! hcitool scan >/dev/null 2>&1; then
        log_error "test.failed" "scanning failed"
        return 1
    fi
    
    # Test pairing functionality (if test device MAC is provided)
    local test_mac=$(get_config_value "$CONFIG_FILE" ".test.device_mac")
    if [ -n "$test_mac" ]; then
        if ! bluetoothctl pair "$test_mac" >/dev/null 2>&1; then
            log_error "test.pairing"
            return 1
        fi
    fi
    
    # Check if Docker container is running and healthy
    if ! docker ps | grep -q "jade-bluetooth"; then
        log_error "test.container"
        return 1
    fi
    
    # Check container logs for errors
    if docker logs jade-bluetooth 2>&1 | grep -i "error"; then
        log_error "test.container_logs"
        return 1
    fi
    
    log_info "$(get_message "info.tests_passed")"
    return 0
}

# Function to rollback changes
rollback_bluetooth() {
    log_info "$(get_message "info.rollback.start")"
    
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    local config_file=$(get_config_value "$CONFIG_FILE" ".service.config_file")
    local systemd_unit=$(get_config_value "$CONFIG_FILE" ".service.systemd_unit")
    local backup_dir=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
    local keep_versions=$(get_config_value "$CONFIG_FILE" ".deployment.rollback.keep_versions")
    local compose_file=$(get_config_value "$CONFIG_FILE" ".docker.compose_file")
    
    # Stop Docker container/compose
    if [ -f "$compose_file" ]; then
        if ! docker-compose -f "$compose_file" down; then
            log_error "deployment.rollback" "Failed to stop docker-compose services"
            return 1
        fi
    elif docker ps -a | grep -q "$component"; then
        if ! docker rm -f "$component"; then
            log_error "deployment.rollback" "Failed to remove container"
            return 1
        fi
    fi
    
    # Find latest backup
    local latest_backup=$(ls -t "${backup_dir}/$(basename "$config_file")".* 2>/dev/null | head -n 1)
    if [ -n "$latest_backup" ]; then
        if ! sudo cp "$latest_backup" "$config_file"; then
            log_error "deployment.config_restore"
            return 1
        fi
        
        # Cleanup old backups keeping specified number of versions
        if [ -n "$keep_versions" ] && [ "$keep_versions" -gt 0 ]; then
            ls -t "${backup_dir}/$(basename "$config_file")".* 2>/dev/null | 
            tail -n +$((keep_versions + 1)) | 
            xargs -r rm --
        fi
    else
        log_error "deployment.rollback" "No backup found"
        return 1
    fi
    
    # Restart bluetooth service
    if ! sudo systemctl restart "$systemd_unit"; then
        log_error "service.start"
        return 1
    fi
    
    # Update deployment status
    update_deployment_status "bluetooth" "rolled_back" "$JADE_BLUETOOTH_VERSION"
    
    return 0
}

# Main setup function
setup_bluetooth() {
    log_info "$(get_message "info.setup_start")"
    
    # Initialize progress tracking
    init_progress 7
    
    # Check prerequisites
    update_progress "Checking prerequisites"
    if ! check_prerequisites; then
        return 1
    fi
    
    # Create required directories
    update_progress "Creating required directories"
    if ! create_directories; then
        return 1
    fi
    
    # Create backup if already deployed
    update_progress "Creating backup"
    local status=$(get_deployment_status "bluetooth")
    if [ "$status" != "not_deployed" ]; then
        local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        create_backup "bluetooth" "$backup_location"
    fi
    
    # Install required packages
    update_progress "Installing required packages"
    if ! install_packages; then
        return 1
    fi
    
    # Configure bluetooth service
    update_progress "Configuring Bluetooth service"
    if ! configure_service; then
        return 1
    fi
    
    # Setup Docker container
    update_progress "Setting up Docker container"
    if ! setup_docker; then
        return 1
    fi
    
    # Run tests if enabled
    if [ "$(get_config_value "$CONFIG_FILE" ".deployment.post_deploy.test_enabled")" = "true" ]; then
        update_progress "Running Bluetooth tests"
        local test_timeout=$(get_config_value "$CONFIG_FILE" ".deployment.post_deploy.test_timeout")
        if ! timeout "$test_timeout" test_bluetooth; then
            if [ $? -eq 124 ]; then
                log_warn "test.timeout" "$test_timeout"
            else
                return 1
            fi
        fi
    fi
    
    # Update deployment status
    update_deployment_status "bluetooth" "deployed" "$JADE_BLUETOOTH_VERSION"
    
    log_info "$(get_message "info.setup_complete")"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set up error handling
    setup_error_handling
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remove)
                if ! rollback_bluetooth; then
                    exit 1
                fi
                exit 0
                ;;
            --check)
                status=$(get_deployment_status "bluetooth")
                if [ "$status" = "deployed" ]; then
                    log_info "deployment.status" "$status"
                    exit 0
                else
                    log_info "deployment.status" "not_deployed"
                    exit 1
                fi
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
    
    # Run setup
    if ! setup_bluetooth; then
        log_error "Setup failed"
        exit 1
    fi
fi
