#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "hid_test"

# Load configuration
CONFIG_FILE=$(load_config "hid")
if [ $? -ne 0 ]; then
    log_error "Failed to load HID configuration"
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
    
    # Test Python HID modules
    if ! python3 -c "import hid, usb" 2>/dev/null; then
        log_error "package.dependency" "Python HID/USB modules"
        return 1
    fi
    
    return 0
}

# Test udev configuration
test_udev() {
    log_info "Testing udev configuration"
    
    # Check rules file
    local rules_file=$(get_config_value "$CONFIG_FILE" ".hid.udev_rules.file")
    if [ ! -f "$rules_file" ]; then
        log_error "udev.rules"
        return 1
    fi
    
    # Check file permissions
    local rules_mode=$(get_config_value "$CONFIG_FILE" ".hid.udev_rules.mode")
    local actual_mode=$(stat -c "%a" "$rules_file")
    if [ "$actual_mode" != "$rules_mode" ]; then
        log_error "udev.permission"
        return 1
    fi
    
    # Verify rules content
    if ! grep -q "SUBSYSTEM==\"input\"" "$rules_file"; then
        log_error "udev.rules"
        return 1
    fi
    
    # Check if udev is active
    if ! systemctl is-active --quiet udev; then
        log_error "udev.reload"
        return 1
    fi
    
    return 0
}

# Test keyboard device
test_keyboard() {
    log_info "Testing keyboard device"
    
    # Find keyboard device
    local keyboard=$(ls /dev/input/by-id/*-kbd 2>/dev/null | head -n1)
    if [ -z "$keyboard" ]; then
        log_error "hardware.keyboard"
        return 1
    fi
    
    # Check permissions
    local perms=$(stat -c "%a" "$keyboard")
    local required_perms=$(get_config_value "$CONFIG_FILE" ".hid.devices[] | select(.type==\"keyboard\") | .permissions")
    if [ "$perms" != "$required_perms" ]; then
        log_error "hardware.permissions"
        return 1
    fi
    
    # Test device access
    if ! evtest --query "$keyboard" EV_KEY; then
        log_error "test.keyboard"
        return 1
    fi
    
    return 0
}

# Test mouse device
test_mouse() {
    log_info "Testing mouse device"
    
    # Find mouse device
    local mouse=$(ls /dev/input/by-id/*-mouse 2>/dev/null | head -n1)
    if [ -z "$mouse" ]; then
        log_error "hardware.mouse"
        return 1
    fi
    
    # Check permissions
    local perms=$(stat -c "%a" "$mouse")
    local required_perms=$(get_config_value "$CONFIG_FILE" ".hid.devices[] | select(.type==\"mouse\") | .permissions")
    if [ "$perms" != "$required_perms" ]; then
        log_error "hardware.permissions"
        return 1
    fi
    
    # Test device access
    if ! evtest --query "$mouse" EV_REL; then
        log_error "test.mouse"
        return 1
    fi
    
    return 0
}

# Test joystick device (optional)
test_joystick() {
    log_info "Testing joystick device"
    
    # Find joystick device
    local joystick=$(ls /dev/input/by-id/*-joystick 2>/dev/null | head -n1)
    if [ -n "$joystick" ]; then
        # Check permissions
        local perms=$(stat -c "%a" "$joystick")
        local required_perms=$(get_config_value "$CONFIG_FILE" ".hid.devices[] | select(.type==\"joystick\") | .permissions")
        if [ "$perms" != "$required_perms" ]; then
            log_error "hardware.permissions"
            return 1
        fi
        
        # Test device access
        if ! evtest --query "$joystick" EV_ABS; then
            log_error "test.joystick" "access failed"
            return 1
        fi
    fi
    
    return 0
}

# Test input latency
test_latency() {
    log_info "Testing input latency"
    
    local max_latency=10  # milliseconds
    local test_duration=1  # second
    
    # Test keyboard latency
    local keyboard=$(ls /dev/input/by-id/*-kbd 2>/dev/null | head -n1)
    if [ -n "$keyboard" ]; then
        local start_time=$(date +%s%N)
        if ! timeout $test_duration evtest --query "$keyboard" EV_KEY; then
            local end_time=$(date +%s%N)
            local latency=$(( ($end_time - $start_time) / 1000000 ))
            if [ $latency -gt $max_latency ]; then
                log_error "test.latency" "$latency" "$max_latency"
                return 1
            fi
        fi
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
    
    # Check container privileges
    if ! docker inspect "$component" | grep -q '"Privileged": true'; then
        log_error "docker.privileged"
        return 1
    fi
    
    # Check device access
    if ! docker exec "$component" ls /dev/input/event* >/dev/null 2>&1; then
        log_error "docker.device"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting HID deployment tests"
    
    # Initialize progress tracking
    init_progress 7
    
    # Run tests
    update_progress "Testing package installation"
    if ! test_packages; then
        return 1
    fi
    
    update_progress "Testing udev configuration"
    if ! test_udev; then
        return 1
    fi
    
    update_progress "Testing keyboard device"
    if ! test_keyboard; then
        return 1
    fi
    
    update_progress "Testing mouse device"
    if ! test_mouse; then
        return 1
    fi
    
    update_progress "Testing joystick device"
    if ! test_joystick; then
        return 1
    fi
    
    update_progress "Testing input latency"
    if ! test_latency; then
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
