#!/bin/bash

# Version declaration
JADE_HID_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"
REQUIRED_SYSTEM_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize logging
init_logging "hid"

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    local error_details="Current version: $JADE_COMMON_VERSION\n"
    error_details+="Required version: $REQUIRED_COMMON_VERSION\n"
    error_details+="Please update common.sh to the required version."
    handle_error "Common library version incompatible" "$error_details" true
fi

# Load configuration
CONFIG_FILE=$(load_config "hid")
if [ $? -ne 0 ]; then
    local error_details="Failed to load configuration from: hid\n"
    error_details+="Please ensure the configuration file exists and is valid."
    handle_error "Failed to load HID configuration" "$error_details" true
fi

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

# Function to check prerequisites
check_prerequisites() {
    log_info "prerequisites.checking"
    
    # Check if system component is deployed
    local system_status=$(get_deployment_status "system")
    if [ "$system_status" != "deployed" ]; then
        local error_details="System component status: $system_status\n"
        error_details+="Required status: deployed\n"
        error_details+="Please ensure the system component is deployed first."
        handle_error "System component is not deployed" "$error_details" true
        return 1
    fi
    
    # Check system version
    local system_version=$(get_config_value "$(load_config "system")" ".version")
    if ! check_version "$system_version" "$REQUIRED_SYSTEM_VERSION"; then
        local error_details="Current system version: $system_version\n"
        error_details+="Required version: $REQUIRED_SYSTEM_VERSION\n"
        error_details+="Please update the system component to the required version."
        handle_error "System version incompatible" "$error_details" true
        return 1
    fi
    
    # Check for required devices
    if ! ls /dev/input/by-id/*-kbd 2>/dev/null; then
        log_warn "device.not_found" "keyboard"
    fi
    if ! ls /dev/input/by-id/*-mouse 2>/dev/null; then
        log_warn "device.not_found" "mouse"
    fi
    
    log_info "prerequisites.passed"
    return 0
}

# Function to install required packages
install_packages() {
    log_info "packages.installing"
    
    # Update package lists
    local output
    if ! output=$(apt-get update 2>&1); then
        handle_error "Failed to update package lists" "$output" true
        return 1
    fi
    
    # Get package list from config
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    
    # Install each package
    for pkg in "${packages[@]}"; do
        log_info "packages.installing_specific" "$pkg"
        if ! output=$(apt-get install -y "$pkg" 2>&1); then
            local error_details="Failed to install package: $pkg\n"
            error_details+="Command output:\n$output"
            handle_error "Package installation failed" "$error_details" true
            return 1
        fi
    done
    
    log_info "packages.complete"
    return 0
}

# Function to configure udev rules
configure_udev() {
    log_info "udev.configuring"
    
    local rules_file=$(get_config_value "$CONFIG_FILE" ".hid.udev_rules.file")
    local rules_mode=$(get_config_value "$CONFIG_FILE" ".hid.udev_rules.mode")
    
    local output
    # Create udev rules
    if ! output=$(cat > "$rules_file" << EOF
# Jade HID udev rules
# Keyboard devices
SUBSYSTEM=="input", GROUP="input", MODE="0666", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1"

# Mouse devices
SUBSYSTEM=="input", GROUP="input", MODE="0666", KERNEL=="event*", ENV{ID_INPUT_MOUSE}=="1"

# Joystick devices
SUBSYSTEM=="input", GROUP="input", MODE="0666", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1"

# Generic HID devices
SUBSYSTEM=="hidraw", GROUP="plugdev", MODE="0666"
SUBSYSTEM=="usb", ATTRS{bInterfaceClass}=="03", GROUP="plugdev", MODE="0666"
EOF
2>&1); then
        local error_details="Failed to create udev rules file: $rules_file\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to create udev rules" "$error_details" true
        return 1
    fi
    
    # Set permissions
    if ! output=$(chmod "$rules_mode" "$rules_file" 2>&1); then
        local error_details="Failed to set permissions on: $rules_file\n"
        error_details+="Attempted mode: $rules_mode\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to set udev rules permissions" "$error_details" true
        return 1
    fi
    
    # Reload udev rules
    log_info "udev.reloading"
    if ! output=$(udevadm control --reload-rules 2>&1); then
        local error_details="Failed to reload udev rules\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to reload udev rules" "$error_details" true
        return 1
    fi
    
    # Trigger udev events
    if ! output=$(udevadm trigger 2>&1); then
        local error_details="Failed to trigger udev events\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to trigger udev events" "$error_details" true
        return 1
    fi
    
    log_info "udev.complete"
    return 0
}

# Function to configure devices
configure_devices() {
    log_info "devices.scanning"
    
    # Get device configurations
    local devices=($(get_config_value "$CONFIG_FILE" ".hid.devices[].type"))
    local permissions=($(get_config_value "$CONFIG_FILE" ".hid.devices[].permissions"))
    
    # Configure each device type
    for i in "${!devices[@]}"; do
        local device_type="${devices[$i]}"
        local device_perms="${permissions[$i]}"
        
        # Find devices of this type
        local device_path="/dev/input/by-id/*-${device_type}"
        if ls $device_path >/dev/null 2>&1; then
            log_info "devices.found" "$device_type" "$(ls $device_path | wc -l) found"
            
            # Set permissions
            for dev in $(ls $device_path); do
                log_info "devices.configuring" "$dev"
                local output
                if ! output=$(chmod "$device_perms" "$dev" 2>&1); then
                    local error_details="Failed to set permissions on device: $dev\n"
                    error_details+="Attempted permissions: $device_perms\n"
                    error_details+="Command output:\n$output"
                    handle_error "Failed to set device permissions" "$error_details" true
                    return 1
                fi
            done
        else
            # Only error if device is required
            local required=$(get_config_value "$CONFIG_FILE" ".hid.devices[] | select(.type==\"$device_type\") | .required")
            if [ "$required" = "true" ]; then
                local error_details="Required device type not found: $device_type\n"
                error_details+="Searched path: $device_path\n"
                error_details+="Please ensure the device is connected and recognized by the system."
                handle_error "Required device not found" "$error_details" true
                return 1
            fi
        fi
    done
    
    log_info "devices.complete"
    return 0
}

# Function to setup Docker container
setup_docker() {
    log_info "docker.setup"
    
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    
    local output
    # Check if container exists and remove it
    if docker ps -a | grep -q "$component"; then
        if ! output=$(docker rm -f "$component" 2>&1); then
            local error_details="Failed to remove existing container: $component\n"
            error_details+="Command output:\n$output"
            handle_error "Failed to remove Docker container" "$error_details" true
            return 1
        fi
    fi
    
    # Start container
    log_info "docker.starting"
    if ! output=$(start_docker_component "$component" 2>&1); then
        local error_details="Failed to start Docker container: $component\n"
        error_details+="Command output:\n$output"
        handle_error "Failed to start Docker container" "$error_details" true
        return 1
    fi
    
    log_info "docker.complete"
    return 0
}

# Function to test HID setup
test_hid() {
    log_info "testing"
    
    local output
    # Run post-deployment tests
    if ! output=$(run_tests "hid" "deploy" 2>&1); then
        local error_details="Post-deployment tests failed\n"
        error_details+="Test output:\n$output"
        handle_error "Deployment tests failed" "$error_details" true
        return 1
    fi
    
    log_info "tests_passed"
    return 0
}

# Function to rollback changes
rollback_hid() {
    log_info "deployment.rollback"
    
    # Stop Docker container
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    if ! stop_docker_component "$component"; then
        log_warn "docker.start"
    fi
    
    # Remove udev rules
    local rules_file=$(get_config_value "$CONFIG_FILE" ".hid.udev_rules.file")
    rm -f "$rules_file"
    
    # Reload udev rules
    udevadm control --reload-rules || true
    udevadm trigger || true
    
    # Reset device permissions
    for dev in /dev/input/event*; do
        chmod 660 "$dev" || true
    done
    
    # Update deployment status
    update_deployment_status "hid" "rolled_back" "$JADE_HID_VERSION"
    
    local output
    # Run rollback tests
    if ! output=$(run_tests "hid" "rollback" 2>&1); then
        local error_details="Rollback tests failed\n"
        error_details+="Test output:\n$output"
        handle_error "Rollback tests failed" "$error_details" true
        return 1
    fi
    
    return 0
}

# Main setup function
setup_hid() {
    log_info "setup_start"
    
    # Initialize progress tracking
    init_progress 7
    
    # Check prerequisites
    update_progress "Checking prerequisites"
    if ! check_prerequisites; then
        return 1
    fi
    
    # Create backup if already deployed
    update_progress "Creating backup"
    local status=$(get_deployment_status "hid")
    if [ "$status" != "not_deployed" ]; then
        local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        create_backup "hid" "$backup_location"
    fi
    
    # Install required packages
    update_progress "Installing required packages"
    if ! install_packages; then
        return 1
    fi
    
    # Configure udev rules
    update_progress "Configuring udev rules"
    if ! configure_udev; then
        return 1
    fi
    
    # Configure devices
    update_progress "Configuring HID devices"
    if ! configure_devices; then
        return 1
    fi
    
    # Setup Docker container
    update_progress "Setting up Docker container"
    if ! setup_docker; then
        return 1
    fi
    
    # Test the setup
    update_progress "Running HID tests"
    if ! test_hid; then
        return 1
    fi
    
    # Update deployment status
    update_deployment_status "hid" "deployed" "$JADE_HID_VERSION"
    
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
                if ! rollback_hid; then
                    exit 1
                fi
                exit 0
                ;;
            --check)
                status=$(get_deployment_status "hid")
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
    if ! setup_hid; then
        local error_details="HID setup failed\n"
        error_details+="Please check the logs for detailed error information."
        handle_error "Setup failed" "$error_details" true
        exit 1
    fi
fi
