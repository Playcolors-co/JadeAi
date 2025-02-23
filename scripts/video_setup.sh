#!/bin/bash

# Version declaration
JADE_VIDEO_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"
REQUIRED_SYSTEM_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize logging
init_logging "video"

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

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    handle_error "Common version check failed" "Required: $REQUIRED_COMMON_VERSION, Current: $JADE_COMMON_VERSION" true
fi

# Load configuration
CONFIG_FILE=$(load_config "video")
if [ $? -ne 0 ]; then
    handle_error "Failed to load video configuration" "Configuration file could not be loaded" true
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "prerequisites.checking"
    
    # Check if Docker is running
    if ! systemctl is-active --quiet docker; then
        handle_error "Docker is not running" "Docker service is not active" true
        return 1
    fi
    
    # Check for video devices
    if ! ls /dev/video* >/dev/null 2>&1; then
        log_warn "device.not_found"
        # Continue anyway, as video devices are optional
        return 0
    fi
    
    log_info "prerequisites.passed"
    return 0
}

# Function to install required packages
install_packages() {
    log_info "packages.installing"
    
    # Update package lists (redirect output to log file)
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
        local output
        if ! output=$(DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>&1); then
            handle_error "Failed to install package" "Package: $pkg\n$output" true
            return 1
        fi
    done
    
    log_info "packages.complete"
    return 0
}

# Function to configure video devices
configure_devices() {
    log_info "devices.scanning"
    
    # Get device configuration
    local device_path=$(get_config_value "$CONFIG_FILE" ".video.devices.path")
    local device_perms=$(get_config_value "$CONFIG_FILE" ".video.devices.permissions")
    
    # Find video devices
    local devices=($(ls ${device_path} 2>/dev/null))
    if [ ${#devices[@]} -eq 0 ]; then
        log_warn "hardware.not_found"
        # Continue anyway, as video devices are optional
        return 0
    fi
    
    # Configure each device (redirect output to log file)
    for device in "${devices[@]}"; do
        log_info "devices.configuring" "$device"
        
        # Set permissions
        local output
        if ! output=$(chmod "$device_perms" "$device" 2>&1); then
            handle_error "Failed to set device permissions" "Device: $device\nPermissions: $device_perms\n$output" false
            # Continue anyway as this device might not be accessible
            continue
        fi
        
        # Test device access
        if ! v4l2-ctl --device="$device" --all >> "$LOG_FILE" 2>&1; then
            log_warn "device.open" "$device"
            # Continue anyway as this device might not be working
            continue
        fi
        
        # Check supported formats
        local required_format=$(get_config_value "$CONFIG_FILE" ".video.formats[] | select(.required==true) | .name")
        if ! v4l2-ctl --device="$device" --list-formats >> "$LOG_FILE" 2>&1 || ! grep -q "$required_format" "$LOG_FILE"; then
            log_warn "device.format"
            # Continue anyway as this device might not support required format
            continue
        fi
        
        log_info "devices.found" "$device"
    done
    
    log_info "devices.complete"
    return 0
}

# Function to setup Docker container
setup_docker() {
    log_info "docker.setup"
    
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    
    # Check if container exists and remove it
    if docker ps -a | grep -q "$component"; then
    local output
    if ! output=$(docker rm -f "$component" 2>&1); then
        handle_error "Failed to remove existing container" "Container: $component\n$output" true
        return 1
    fi
    fi
    
    # Start container
    log_info "docker.starting"
    # Export version for envsubst and ensure it's properly expanded
    export JADE_VIDEO_VERSION
    local expanded_image=$(get_config_value "$CONFIG_FILE" ".docker.components[0].image" | envsubst)
    local output
    if ! output=$(start_docker_component "$component" "$expanded_image" 2>&1); then
        handle_error "Failed to start Docker component" "Component: $component\nImage: $expanded_image\n$output" true
        return 1
    fi
    unset JADE_VIDEO_VERSION
    
    log_info "docker.complete"
    return 0
}

# Function to test video setup
test_video() {
    log_info "testing"
    
    # Run post-deployment tests
    local output
    if ! output=$(run_tests "video" "deploy" 2>&1); then
        handle_error "Video tests failed" "$output" true
        return 1
    fi
    
    log_info "tests_passed"
    return 0
}

# Function to rollback changes
rollback_video() {
    log_info "deployment.rollback"
    
    # Stop Docker container
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    if ! stop_docker_component "$component"; then
        log_warn "docker.start"
    fi
    
    # Reset device permissions
    local device_path=$(get_config_value "$CONFIG_FILE" ".video.devices.path")
    local devices=($(ls ${device_path} 2>/dev/null))
    for device in "${devices[@]}"; do
        chmod 660 "$device" || true
    done
    
    # Update deployment status
    update_deployment_status "video" "rolled_back" "$JADE_VIDEO_VERSION"
    
    # Run rollback tests
    if ! run_tests "video" "rollback"; then
        log_error "test.failed"
        return 1
    fi
    
    return 0
}

# Main setup function
setup_video() {
    log_info "setup_start"
    
    # Initialize progress tracking
    init_progress 6
    
    # Check prerequisites
    update_progress "Checking prerequisites"
    if ! check_prerequisites; then
        return 1
    fi
    
    # Create backup if already deployed
    update_progress "Creating backup"
    local status=$(get_deployment_status "video")
    if [ "$status" != "not_deployed" ]; then
        local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        create_backup "video" "$backup_location"
    fi
    
    # Install required packages
    update_progress "Installing required packages"
    if ! install_packages; then
        return 1
    fi
    
    # Configure video devices
    update_progress "Configuring video devices"
    if ! configure_devices; then
        return 1
    fi
    
    # Setup Docker container
    update_progress "Setting up Docker container"
    if ! setup_docker; then
        return 1
    fi
    
    # Test the setup
    update_progress "Running video tests"
    if ! test_video; then
        return 1
    fi
    
    # Update deployment status
    update_deployment_status "video" "deployed" "$JADE_VIDEO_VERSION"
    
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
                if ! rollback_video; then
                    exit 1
                fi
                exit 0
                ;;
            --check)
                status=$(get_deployment_status "video")
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
    if ! setup_video; then
        log_error "Setup failed"
        exit 1
    fi
fi
