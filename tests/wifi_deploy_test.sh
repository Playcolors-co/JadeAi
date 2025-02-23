#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "wifi_test"

# Load configuration
CONFIG_FILE=$(load_config "wifi")
if [ $? -ne 0 ]; then
    log_error "Failed to load WiFi configuration"
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

# Test wireless hardware
test_hardware() {
    log_info "Testing wireless hardware"
    
    # Check if wireless is enabled
    if ! rfkill list wifi | grep -q "unblocked"; then
        log_error "hardware.blocked"
        return 1
    fi
    
    # Check for wireless interfaces
    if ! iw dev | grep -q "Interface"; then
        log_error "hardware.not_found"
        return 1
    fi
    
    # Check interface capabilities
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    if ! iw phy | grep -A 2 "Supported interface modes" | grep -q "AP"; then
        log_error "hardware.unsupported"
        return 1
    fi
    
    return 0
}

# Test netplan configuration
test_netplan() {
    log_info "Testing netplan configuration"
    
    # Check netplan file
    local netplan_file=$(get_config_value "$CONFIG_FILE" ".wifi.netplan.file")
    if [ ! -f "$netplan_file" ]; then
        log_error "netplan.generate"
        return 1
    fi
    
    # Check file permissions
    local netplan_mode=$(get_config_value "$CONFIG_FILE" ".wifi.netplan.mode")
    local actual_mode=$(stat -c "%a" "$netplan_file")
    if [ "$actual_mode" != "$netplan_mode" ]; then
        log_error "netplan.permission"
        return 1
    fi
    
    # Validate configuration
    if ! netplan try --timeout 1 >/dev/null 2>&1; then
        log_error "netplan.validate"
        return 1
    fi
    
    return 0
}

# Test access point configuration
test_ap() {
    log_info "Testing access point configuration"
    
    # Check hostapd configuration
    local hostapd_file=$(get_config_value "$CONFIG_FILE" ".wifi.hostapd.file")
    if [ ! -f "$hostapd_file" ]; then
        log_error "ap.config"
        return 1
    fi
    
    # Check hostapd service
    if ! systemctl is-active --quiet hostapd; then
        log_error "ap.start"
        return 1
    fi
    
    # Check AP interface
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    if ! ip addr show "$ap_if" | grep -q "UP"; then
        log_error "interface.up" "$ap_if"
        return 1
    fi
    
    # Check AP IP address
    local ap_ip=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.ip")
    if ! ip addr show "$ap_if" | grep -q "$ap_ip"; then
        log_error "interface.address" "$ap_if"
        return 1
    fi
    
    return 0
}

# Test DHCP configuration
test_dhcp() {
    log_info "Testing DHCP configuration"
    
    # Check dnsmasq configuration
    local dnsmasq_file=$(get_config_value "$CONFIG_FILE" ".wifi.dnsmasq.file")
    if [ ! -f "$dnsmasq_file" ]; then
        log_error "ap.dhcp"
        return 1
    fi
    
    # Check dnsmasq service
    if ! systemctl is-active --quiet dnsmasq; then
        log_error "ap.dhcp"
        return 1
    fi
    
    # Check DHCP range
    local dhcp_start=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.dhcp.start")
    local dhcp_end=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.dhcp.end")
    if ! grep -q "dhcp-range=${dhcp_start},${dhcp_end}" "$dnsmasq_file"; then
        log_error "ap.dhcp"
        return 1
    fi
    
    return 0
}

# Test client interface
test_client() {
    log_info "Testing client interface"
    
    local client_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.client.name")
    if iw dev | grep -q "$client_if"; then
        # Check interface state
        if ! ip link show "$client_if" | grep -q "UP"; then
            log_error "interface.up" "$client_if"
            return 1
        fi
        
        # Check scanning capability
        if ! iw dev "$client_if" scan >/dev/null 2>&1; then
            log_error "client.scan"
            return 1
        fi
    else
        log_warn "interface.not_found" "$client_if"
    fi
    
    return 0
}

# Test network throughput
test_throughput() {
    log_info "Testing network throughput"
    
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    local min_throughput=50  # Mbps
    
    # Test AP interface throughput
    if command -v iperf3 >/dev/null; then
        # Start iperf server
        iperf3 -s -D
        
        # Test throughput
        local result=$(iperf3 -c localhost -i 0 -t 1 | grep "sender" | awk '{print $7}')
        kill $(pgrep iperf3)
        
        if [ -n "$result" ] && [ "${result%.*}" -lt "$min_throughput" ]; then
            log_error "test.throughput" "$result" "$min_throughput"
            return 1
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
    
    # Check network mode
    if ! docker inspect "$component" | grep -q '"NetworkMode": "host"'; then
        log_error "docker.network"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting WiFi deployment tests"
    
    # Initialize progress tracking
    init_progress 7
    
    # Run tests
    update_progress "Testing package installation"
    if ! test_packages; then
        return 1
    fi
    
    update_progress "Testing wireless hardware"
    if ! test_hardware; then
        return 1
    fi
    
    update_progress "Testing netplan configuration"
    if ! test_netplan; then
        return 1
    fi
    
    update_progress "Testing access point"
    if ! test_ap; then
        return 1
    fi
    
    update_progress "Testing DHCP server"
    if ! test_dhcp; then
        return 1
    fi
    
    update_progress "Testing network performance"
    if ! test_throughput; then
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
