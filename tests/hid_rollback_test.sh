#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "hid_rollback_test"

# Load configuration
CONFIG_FILE=$(load_config "hid")
if [ $? -ne 0 ]; then
    log_error "Failed to load HID configuration"
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

# Test udev cleanup
test_udev_cleanup() {
    log_info "Testing udev cleanup"
    
    # Check if rules file is removed
    local rules_file=$(get_config_value "$CONFIG_FILE" ".hid.udev_rules.file")
    if [ -f "$rules_file" ]; then
        log_error "udev rules file still exists"
        return 1
    fi
    
    # Check if custom rules are removed
    if grep -r "jade-hid" /etc/udev/rules.d/ >/dev/null 2>&1; then
        log_error "Custom udev rules still exist"
        return 1
    fi
    
    # Verify udev is running
    if ! systemctl is-active --quiet udev; then
        log_error "udev service not running"
        return 1
    fi
    
    return 0
}

# Test device permissions cleanup
test_device_permissions() {
    log_info "Testing device permissions cleanup"
    
    # Check keyboard permissions
    for kbd in /dev/input/by-id/*-kbd; do
        if [ -e "$kbd" ]; then
            local perms=$(stat -c "%a" "$kbd")
            if [ "$perms" != "660" ]; then
                log_error "Keyboard permissions not reset: $kbd"
                return 1
            fi
        fi
    done
    
    # Check mouse permissions
    for mouse in /dev/input/by-id/*-mouse; do
        if [ -e "$mouse" ]; then
            local perms=$(stat -c "%a" "$mouse")
            if [ "$perms" != "660" ]; then
                log_error "Mouse permissions not reset: $mouse"
                return 1
            fi
        fi
    done
    
    # Check joystick permissions
    for joy in /dev/input/by-id/*-joystick; do
        if [ -e "$joy" ]; then
            local perms=$(stat -c "%a" "$joy")
            if [ "$perms" != "660" ]; then
                log_error "Joystick permissions not reset: $joy"
                return 1
            fi
        fi
    done
    
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
    local image=$(get_config_value "$CONFIG_FILE" ".docker.components[0].image" | sed "s/\${version}/$JADE_HID_VERSION/")
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
    local status=$(get_deployment_status "hid")
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
    if [ ! -f "$backup_location/$latest_backup/99-jade-hid.rules" ]; then
        log_error "Backup missing udev rules"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting HID rollback tests"
    
    # Initialize progress tracking
    init_progress 7
    
    # Run tests
    update_progress "Testing package removal"
    if ! test_packages_removed; then
        return 1
    fi
    
    update_progress "Testing udev cleanup"
    if ! test_udev_cleanup; then
        return 1
    fi
    
    update_progress "Testing device permissions"
    if ! test_device_permissions; then
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
