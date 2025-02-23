#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "wifi_rollback_test"

# Load configuration
CONFIG_FILE=$(load_config "wifi")
if [ $? -ne 0 ]; then
    log_error "Failed to load WiFi configuration"
    exit 1
fi

# Test package removal
test_packages_removed() {
    log_info "Testing package removal"
    
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    for pkg in "${packages[@]}"; do
        # Only check packages marked as required
        local required=$(get_config_value "$CONFIG_FILE" ".packages[] | select(.name==\"$pkg\") | .required")
        if [ "$required" = "true" ] && dpkg -l | grep -q "^ii  $pkg "; then
            log_error "Package still installed: $pkg"
            return 1
        fi
    done
    
    return 0
}

# Test netplan cleanup
test_netplan_cleanup() {
    log_info "Testing netplan cleanup"
    
    # Check if netplan file is removed
    local netplan_file=$(get_config_value "$CONFIG_FILE" ".wifi.netplan.file")
    if [ -f "$netplan_file" ]; then
        log_error "Netplan configuration still exists"
        return 1
    fi
    
    # Check if custom configurations are removed
    if grep -r "jade-wifi" /etc/netplan/ >/dev/null 2>&1; then
        log_error "Custom netplan configurations still exist"
        return 1
    fi
    
    return 0
}

# Test hostapd cleanup
test_hostapd_cleanup() {
    log_info "Testing hostapd cleanup"
    
    # Check if hostapd file is removed
    local hostapd_file=$(get_config_value "$CONFIG_FILE" ".wifi.hostapd.file")
    if [ -f "$hostapd_file" ]; then
        log_error "Hostapd configuration still exists"
        return 1
    fi
    
    # Check if service is stopped
    if systemctl is-active --quiet hostapd; then
        log_error "Hostapd service still running"
        return 1
    fi
    
    return 0
}

# Test dnsmasq cleanup
test_dnsmasq_cleanup() {
    log_info "Testing dnsmasq cleanup"
    
    # Check if dnsmasq file is removed
    local dnsmasq_file=$(get_config_value "$CONFIG_FILE" ".wifi.dnsmasq.file")
    if [ -f "$dnsmasq_file" ]; then
        log_error "Dnsmasq configuration still exists"
        return 1
    fi
    
    # Check if custom configurations are removed
    if grep -r "jade-wifi" /etc/dnsmasq.d/ >/dev/null 2>&1; then
        log_error "Custom dnsmasq configurations still exist"
        return 1
    fi
    
    return 0
}

# Test interface cleanup
test_interface_cleanup() {
    log_info "Testing interface cleanup"
    
    # Check client interface
    local client_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.client.name")
    if ip link show "$client_if" 2>/dev/null | grep -q "UP"; then
        log_error "Client interface still up"
        return 1
    fi
    
    # Check AP interface
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    if ip link show "$ap_if" 2>/dev/null | grep -q "UP"; then
        log_error "AP interface still up"
        return 1
    fi
    
    # Check for any remaining IP configurations
    local ap_ip=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.ip")
    if ip addr show | grep -q "$ap_ip"; then
        log_error "AP IP address still configured"
        return 1
    fi
    
    return 0
}

# Test Docker cleanup
test_docker_cleanup() {
    log_info "Testing Docker cleanup"
    
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    
    # Check if container is removed
    if docker ps -a | grep -q "$component"; then
        log_error "Docker container still exists"
        return 1
    fi
    
    # Check if image is removed
    local image=$(get_config_value "$CONFIG_FILE" ".docker.components[0].image" | sed "s/\${version}/$JADE_WIFI_VERSION/")
    if docker images | grep -q "$image"; then
        log_error "Docker image still exists"
        return 1
    fi
    
    return 0
}

# Test directory cleanup
test_directories_cleaned() {
    log_info "Testing directory cleanup"
    
    local dirs=($(get_config_value "$CONFIG_FILE" ".directories[].path"))
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ] && [ ! -z "$(ls -A "$dir")" ]; then
            log_error "Directory not empty: $dir"
            return 1
        fi
    done
    
    return 0
}

# Test deployment status
test_deployment_status() {
    log_info "Testing deployment status"
    
    # Check deployment status
    local status=$(get_deployment_status "wifi")
    if [ "$status" = "deployed" ]; then
        log_error "Component still marked as deployed"
        return 1
    fi
    
    # Check status file
    local status_file=$(get_config_value "$CONFIG_FILE" ".status.file")
    if [ -f "$status_file" ]; then
        log_error "Status file still exists"
        return 1
    fi
    
    return 0
}

# Test backup creation
test_backup() {
    log_info "Testing backup creation"
    
    local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
    if [ ! -d "$backup_location" ]; then
        log_error "Backup directory not found"
        return 1
    fi
    
    # Check if at least one backup exists
    if [ -z "$(ls -A "$backup_location")" ]; then
        log_error "No backups found"
        return 1
    fi
    
    # Check backup contents
    local latest_backup=$(ls -t "$backup_location" | head -n1)
    if [ ! -f "$backup_location/$latest_backup/hostapd.conf" ]; then
        log_error "Backup missing hostapd configuration"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting WiFi rollback tests"
    
    # Initialize progress tracking
    init_progress 9
    
    # Run tests
    update_progress "Testing package removal"
    if ! test_packages_removed; then
        return 1
    fi
    
    update_progress "Testing netplan cleanup"
    if ! test_netplan_cleanup; then
        return 1
    fi
    
    update_progress "Testing hostapd cleanup"
    if ! test_hostapd_cleanup; then
        return 1
    fi
    
    update_progress "Testing dnsmasq cleanup"
    if ! test_dnsmasq_cleanup; then
        return 1
    fi
    
    update_progress "Testing interface cleanup"
    if ! test_interface_cleanup; then
        return 1
    fi
    
    update_progress "Testing Docker cleanup"
    if ! test_docker_cleanup; then
        return 1
    fi
    
    update_progress "Testing directory cleanup"
    if ! test_directories_cleaned; then
        return 1
    fi
    
    update_progress "Testing deployment status"
    if ! test_deployment_status; then
        return 1
    fi
    
    update_progress "Testing backup creation"
    if ! test_backup; then
        return 1
    fi
    
    log_info "All rollback tests passed successfully"
    return 0
}

# Run tests
if ! main; then
    log_error "Rollback tests failed"
    exit 1
fi

exit 0
