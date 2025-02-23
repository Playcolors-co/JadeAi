#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "bluetooth_test"

# Load configuration
CONFIG_FILE=$(load_config "bluetooth")
if [ $? -ne 0 ]; then
    log_error "Failed to load bluetooth configuration"
    exit 1
fi

# Test required packages
test_packages() {
    log_info "Testing required packages"
    
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_error "Package not installed: $pkg"
            return 1
        fi
    done
    
    return 0
}

# Test bluetooth hardware
test_hardware() {
    log_info "Testing Bluetooth hardware"
    
    # Check for bluetooth adapter
    if ! hciconfig 2>/dev/null | grep -q "hci"; then
        log_error "hardware.not_found"
        return 1
    fi
    
    # Check adapter status
    local adapter=$(hciconfig | grep "^hci" | cut -d: -f1)
    if ! hciconfig "$adapter" | grep -q "UP RUNNING"; then
        log_error "hardware.failure"
        return 1
    fi
    
    # Check if adapter is blocked
    if rfkill list bluetooth | grep -q "blocked: yes"; then
        log_error "hardware.blocked"
        return 1
    fi
    
    # Test basic functionality
    if ! hciconfig "$adapter" piscan; then
        log_error "hardware.failure"
        return 1
    fi
    
    return 0
}

# Test bluetooth service
test_service() {
    log_info "Testing Bluetooth service"
    
    local service_name=$(get_config_value "$CONFIG_FILE" ".service.name")
    local config_file=$(get_config_value "$CONFIG_FILE" ".service.config_file")
    
    # Check service status
    if ! systemctl is-active --quiet "$service_name"; then
        log_error "service.start"
        return 1
    fi
    
    # Check configuration file
    if [ ! -f "$config_file" ]; then
        log_error "service.config"
        return 1
    fi
    
    # Verify configuration content
    if ! grep -q "Name = JadeAI Bluetooth" "$config_file"; then
        log_error "service.config"
        return 1
    fi
    
    # Test D-Bus connection
    if ! dbus-send --system --dest=org.bluez --print-reply / org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1; then
        log_error "service.dbus"
        return 1
    fi
    
    return 0
}

# Test Docker container
test_docker() {
    log_info "Testing Docker container"
    
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    
    # Check if container is running
    if ! docker ps | grep -q "$component"; then
        log_error "docker.start"
        return 1
    fi
    
    # Check container logs for errors
    if docker logs "$component" 2>&1 | grep -i "error"; then
        log_error "docker.start"
        return 1
    fi
    
    # Check container network mode
    if ! docker inspect "$component" | grep -q '"NetworkMode": "host"'; then
        log_error "docker.network"
        return 1
    fi
    
    # Check container privileges
    if ! docker inspect "$component" | grep -q '"Privileged": true'; then
        log_error "docker.privileged"
        return 1
    }
    
    return 0
}

# Test deployment status
test_deployment() {
    log_info "Testing deployment status"
    
    # Check deployment status
    local status=$(get_deployment_status "bluetooth")
    if [ "$status" != "deployed" ]; then
        log_error "deployment.status"
        return 1
    fi
    
    # Check required directories
    local dirs=($(get_config_value "$CONFIG_FILE" ".directories[].path"))
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "Directory not found: $dir"
            return 1
        fi
    done
    
    return 0
}

# Main test execution
main() {
    log_info "Starting Bluetooth deployment tests"
    
    # Initialize progress tracking
    init_progress 4
    
    # Run tests
    update_progress "Testing package installation"
    if ! test_packages; then
        return 1
    fi
    
    update_progress "Testing Bluetooth hardware"
    if ! test_hardware; then
        return 1
    fi
    
    update_progress "Testing Bluetooth service"
    if ! test_service; then
        return 1
    fi
    
    update_progress "Testing Docker container"
    if ! test_docker; then
        return 1
    fi
    
    log_info "All deployment tests passed successfully"
    return 0
}

# Run tests
if ! main; then
    log_error "Deployment tests failed"
    exit 1
fi

exit 0
