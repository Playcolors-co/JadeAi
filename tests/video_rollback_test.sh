#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "video_rollback_test"

# Load configuration
CONFIG_FILE=$(load_config "video")
if [ $? -ne 0 ]; then
    log_error "Failed to load video configuration"
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

# Test device cleanup
test_device_cleanup() {
    log_info "Testing device cleanup"
    
    local device_path=$(get_config_value "$CONFIG_FILE" ".video.devices.path")
    local devices=($(ls ${device_path} 2>/dev/null))
    
    for device in "${devices[@]}"; do
        # Check if permissions were reset
        local perms=$(stat -c "%a" "$device")
        if [ "$perms" != "660" ]; then
            log_error "Device permissions not reset: $device"
            return 1
        fi
        
        # Check if device is not in use
        if fuser "$device" >/dev/null 2>&1; then
            log_error "Device still in use: $device"
            return 1
        fi
    done
    
    return 0
}

# Test streaming cleanup
test_streaming_cleanup() {
    log_info "Testing streaming cleanup"
    
    # Check if RTSP port is closed
    local rtsp_port=$(get_config_value "$CONFIG_FILE" ".docker.components[0].ports[0]" | cut -d: -f1)
    if nc -z localhost "$rtsp_port" 2>/dev/null; then
        log_error "RTSP port still open"
        return 1
    fi
    
    # Check if HTTP port is closed
    local http_port=$(get_config_value "$CONFIG_FILE" ".docker.components[0].ports[1]" | cut -d: -f1)
    if nc -z localhost "$http_port" 2>/dev/null; then
        log_error "HTTP port still open"
        return 1
    fi
    
    # Check if any GStreamer processes are running
    if pgrep -f "gst-launch-1.0" >/dev/null; then
        log_error "GStreamer processes still running"
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
    local image=$(get_config_value "$CONFIG_FILE" ".docker.components[0].image" | sed "s/\${version}/$JADE_VIDEO_VERSION/")
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
    
    # Check streams directory
    local streams_dir="/opt/jade/video/streams"
    if [ -d "$streams_dir" ] && [ ! -z "$(ls -A "$streams_dir")" ]; then
        log_error "Streams directory not empty"
        return 1
    fi
    
    return 0
}

# Test deployment status
test_deployment_status() {
    log_info "Testing deployment status"
    
    # Check deployment status
    local status=$(get_deployment_status "video")
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
    if [ ! -d "$backup_location/$latest_backup/streams" ]; then
        log_error "Backup missing streams directory"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting video rollback tests"
    
    # Initialize progress tracking
    init_progress 7
    
    # Run tests
    update_progress "Testing package removal"
    if ! test_packages_removed; then
        return 1
    fi
    
    update_progress "Testing device cleanup"
    if ! test_device_cleanup; then
        return 1
    fi
    
    update_progress "Testing streaming cleanup"
    if ! test_streaming_cleanup; then
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
