#!/bin/bash

# Version declaration
JADE_WIFI_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"
REQUIRED_SYSTEM_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize logging
init_logging "wifi"

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    log_error "prerequisites.version" "$REQUIRED_COMMON_VERSION" "$JADE_COMMON_VERSION"
    exit 1
fi

# Load configuration
CONFIG_FILE=$(load_config "wifi")
if [ $? -ne 0 ]; then
    log_error "Failed to load WiFi configuration"
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "prerequisites.checking"
    
    # Check if system component is deployed
    local system_status=$(get_deployment_status "system")
    if [ "$system_status" != "deployed" ]; then
        log_error "prerequisites.system"
        return 1
    fi
    
    # Check system version
    local system_version=$(get_config_value "$(load_config "system")" ".version")
    if ! check_version "$system_version" "$REQUIRED_SYSTEM_VERSION"; then
        log_error "prerequisites.version" "$REQUIRED_SYSTEM_VERSION" "$system_version"
        return 1
    fi
    
    # Check for wireless interfaces
    if ! iw dev | grep -q "Interface"; then
        log_warn "interface.not_found" "wireless"
    fi
    
    # Check if wireless is blocked
    if rfkill list wifi | grep -q "blocked: yes"; then
        log_error "hardware.blocked"
        return 1
    fi
    
    log_info "prerequisites.passed"
    return 0
}

# Function to install required packages
install_packages() {
    log_info "packages.installing"
    
    # Update package lists
    if ! apt-get update; then
        log_error "package.install" "apt-get update failed"
        return 1
    fi
    
    # Get package list from config
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    
    # Install each package
    for pkg in "${packages[@]}"; do
        log_info "packages.installing_specific" "$pkg"
        if ! apt-get install -y "$pkg"; then
            log_error "package.install" "$pkg"
            return 1
        fi
    done
    
    log_info "packages.complete"
    return 0
}

# Function to configure netplan
configure_netplan() {
    log_info "netplan.configuring"
    
    local netplan_file=$(get_config_value "$CONFIG_FILE" ".wifi.netplan.file")
    local netplan_mode=$(get_config_value "$CONFIG_FILE" ".wifi.netplan.mode")
    local client_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.client.name")
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    
    # Create netplan configuration
    cat > "$netplan_file" << EOF
network:
  version: 2
  renderer: networkd
  wifis:
    ${client_if}:
      dhcp4: true
      optional: true
    ${ap_if}:
      dhcp4: false
      addresses:
        - $(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.ip")/24
EOF
    
    if [ $? -ne 0 ]; then
        log_error "netplan.generate"
        return 1
    fi
    
    # Set permissions
    if ! chmod "$netplan_mode" "$netplan_file"; then
        log_error "netplan.permission"
        return 1
    fi
    
    # Apply configuration
    log_info "netplan.applying"
    if ! netplan generate; then
        log_error "netplan.generate"
        return 1
    fi
    if ! netplan apply; then
        log_error "netplan.apply"
        return 1
    fi
    
    log_info "netplan.complete"
    return 0
}

# Function to configure hostapd
configure_hostapd() {
    log_info "hostapd.configuring"
    
    local hostapd_file=$(get_config_value "$CONFIG_FILE" ".wifi.hostapd.file")
    local hostapd_mode=$(get_config_value "$CONFIG_FILE" ".wifi.hostapd.mode")
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    local ap_ssid=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.ssid")
    local ap_pass=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.password")
    local ap_channel=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.channel")
    
    # Create hostapd configuration
    cat > "$hostapd_file" << EOF
interface=${ap_if}
driver=nl80211
ssid=${ap_ssid}
hw_mode=g
channel=${ap_channel}
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${ap_pass}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    
    if [ $? -ne 0 ]; then
        log_error "ap.config"
        return 1
    fi
    
    # Set permissions
    if ! chmod "$hostapd_mode" "$hostapd_file"; then
        log_error "ap.config"
        return 1
    fi
    
    # Configure service
    if ! systemctl unmask hostapd; then
        log_error "ap.start"
        return 1
    fi
    
    # Start service
    log_info "hostapd.starting"
    if ! systemctl enable --now hostapd; then
        log_error "ap.start"
        return 1
    fi
    
    log_info "hostapd.complete"
    return 0
}

# Function to configure dnsmasq
configure_dnsmasq() {
    log_info "dnsmasq.configuring"
    
    local dnsmasq_file=$(get_config_value "$CONFIG_FILE" ".wifi.dnsmasq.file")
    local dnsmasq_mode=$(get_config_value "$CONFIG_FILE" ".wifi.dnsmasq.mode")
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    local dhcp_start=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.dhcp.start")
    local dhcp_end=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.dhcp.end")
    local dhcp_lease=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.dhcp.lease")
    
    # Create dnsmasq configuration
    cat > "$dnsmasq_file" << EOF
interface=${ap_if}
dhcp-range=${dhcp_start},${dhcp_end},${dhcp_lease}
EOF
    
    if [ $? -ne 0 ]; then
        log_error "ap.dhcp"
        return 1
    fi
    
    # Set permissions
    if ! chmod "$dnsmasq_mode" "$dnsmasq_file"; then
        log_error "ap.dhcp"
        return 1
    fi
    
    # Start service
    log_info "dnsmasq.starting"
    if ! systemctl restart dnsmasq; then
        log_error "ap.dhcp"
        return 1
    fi
    
    log_info "dnsmasq.complete"
    return 0
}

# Function to configure interfaces
configure_interfaces() {
    log_info "interfaces.scanning"
    
    # Configure client interface
    local client_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.client.name")
    if iw dev | grep -q "$client_if"; then
        log_info "interfaces.configuring" "$client_if"
        if ! ip link set "$client_if" up; then
            log_error "interface.up" "$client_if"
            return 1
        fi
    else
        log_warn "interface.not_found" "$client_if"
    fi
    
    # Configure AP interface
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    if iw dev | grep -q "$ap_if"; then
        log_info "interfaces.configuring" "$ap_if"
        if ! ip link set "$ap_if" up; then
            log_error "interface.up" "$ap_if"
            return 1
        fi
    else
        log_error "interface.not_found" "$ap_if"
        return 1
    fi
    
    log_info "interfaces.complete"
    return 0
}

# Function to setup Docker container
setup_docker() {
    log_info "docker.setup"
    
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    
    # Check if container exists and remove it
    if docker ps -a | grep -q "$component"; then
        if ! docker rm -f "$component"; then
            log_error "docker.start"
            return 1
        fi
    fi
    
    # Start container
    log_info "docker.starting"
    if ! start_docker_component "$component"; then
        log_error "docker.start"
        return 1
    fi
    
    log_info "docker.complete"
    return 0
}

# Function to test WiFi setup
test_wifi() {
    log_info "testing"
    
    # Run post-deployment tests
    if ! run_tests "wifi" "deploy"; then
        log_error "test.failed"
        return 1
    fi
    
    log_info "tests_passed"
    return 0
}

# Function to rollback changes
rollback_wifi() {
    log_info "deployment.rollback"
    
    # Stop Docker container
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    if ! stop_docker_component "$component"; then
        log_warn "docker.start"
    fi
    
    # Stop services
    systemctl stop hostapd dnsmasq || true
    
    # Remove configurations
    local netplan_file=$(get_config_value "$CONFIG_FILE" ".wifi.netplan.file")
    local hostapd_file=$(get_config_value "$CONFIG_FILE" ".wifi.hostapd.file")
    local dnsmasq_file=$(get_config_value "$CONFIG_FILE" ".wifi.dnsmasq.file")
    rm -f "$netplan_file" "$hostapd_file" "$dnsmasq_file"
    
    # Reset interfaces
    local client_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.client.name")
    local ap_if=$(get_config_value "$CONFIG_FILE" ".wifi.interfaces.ap.name")
    ip link set "$client_if" down || true
    ip link set "$ap_if" down || true
    
    # Update deployment status
    update_deployment_status "wifi" "rolled_back" "$JADE_WIFI_VERSION"
    
    # Run rollback tests
    if ! run_tests "wifi" "rollback"; then
        log_error "test.failed"
        return 1
    fi
    
    return 0
}

# Main setup function
setup_wifi() {
    log_info "setup_start"
    
    # Initialize progress tracking
    init_progress 8
    
    # Check prerequisites
    update_progress "Checking prerequisites"
    if ! check_prerequisites; then
        return 1
    fi
    
    # Create backup if already deployed
    update_progress "Creating backup"
    local status=$(get_deployment_status "wifi")
    if [ "$status" != "not_deployed" ]; then
        local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        create_backup "wifi" "$backup_location"
    fi
    
    # Install required packages
    update_progress "Installing required packages"
    if ! install_packages; then
        return 1
    fi
    
    # Configure interfaces
    update_progress "Configuring wireless interfaces"
    if ! configure_interfaces; then
        return 1
    fi
    
    # Configure netplan
    update_progress "Configuring Netplan"
    if ! configure_netplan; then
        return 1
    fi
    
    # Configure hostapd
    update_progress "Configuring access point"
    if ! configure_hostapd; then
        return 1
    fi
    
    # Configure dnsmasq
    update_progress "Configuring DHCP server"
    if ! configure_dnsmasq; then
        return 1
    fi
    
    # Setup Docker container
    update_progress "Setting up Docker container"
    if ! setup_docker; then
        return 1
    fi
    
    # Test the setup
    update_progress "Running WiFi tests"
    if ! test_wifi; then
        return 1
    fi
    
    # Update deployment status
    update_deployment_status "wifi" "deployed" "$JADE_WIFI_VERSION"
    
    log_info "setup_complete"
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
                if ! rollback_wifi; then
                    exit 1
                fi
                exit 0
                ;;
            --check)
                status=$(get_deployment_status "wifi")
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
    if ! setup_wifi; then
        log_error "Setup failed"
        exit 1
    fi
fi
