#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "video_test"

# Load configuration
CONFIG_FILE=$(load_config "video")
if [ $? -ne 0 ]; then
    log_error "Failed to load video configuration"
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
    
    # Test GStreamer plugins
    local gst_plugins=("base" "good" "bad" "ugly")
    for plugin in "${gst_plugins[@]}"; do
        if ! gst-inspect-1.0 | grep -q "gstreamer.*${plugin}"; then
            log_error "package.gstreamer" "$plugin"
            return 1
        fi
    done
    
    return 0
}

# Test video hardware
test_hardware() {
    log_info "Testing video hardware"
    
    local device_path=$(get_config_value "$CONFIG_FILE" ".video.devices.path")
    local devices=($(ls ${device_path} 2>/dev/null))
    
    if [ ${#devices[@]} -eq 0 ]; then
        log_error "hardware.not_found"
        return 1
    fi
    
    for device in "${devices[@]}"; do
        # Check device permissions
        local perms=$(stat -c "%a" "$device")
        local required_perms=$(get_config_value "$CONFIG_FILE" ".video.devices.permissions")
        if [ "$perms" != "$required_perms" ]; then
            log_error "hardware.permissions"
            return 1
        fi
        
        # Check if device is accessible
        if ! v4l2-ctl --device="$device" --all >/dev/null 2>&1; then
            log_error "device.open" "$device"
            return 1
        fi
        
        # Check if device is not busy
        if fuser "$device" >/dev/null 2>&1; then
            log_error "hardware.busy"
            return 1
        fi
    done
    
    return 0
}

# Test video formats
test_formats() {
    log_info "Testing video formats"
    
    local device=$(ls $(get_config_value "$CONFIG_FILE" ".video.devices.path") | head -n1)
    
    # Test required formats
    local formats=($(get_config_value "$CONFIG_FILE" ".video.formats[].name"))
    for format in "${formats[@]}"; do
        if ! v4l2-ctl --device="$device" --list-formats | grep -q "$format"; then
            log_error "test.format" "$format"
            return 1
        fi
    done
    
    # Test resolutions
    local resolutions=($(get_config_value "$CONFIG_FILE" ".video.resolutions[]"))
    local resolution_found=false
    for resolution in "${resolutions[@]}"; do
        if v4l2-ctl --device="$device" --list-framesizes=MJPEG | grep -q "$resolution"; then
            resolution_found=true
            break
        fi
    done
    if [ "$resolution_found" = false ]; then
        log_error "device.resolution"
        return 1
    fi
    
    # Test framerates
    local framerates=($(get_config_value "$CONFIG_FILE" ".video.framerates[]"))
    local framerate_found=false
    for framerate in "${framerates[@]}"; do
        if v4l2-ctl --device="$device" --list-frameintervals=MJPEG,${resolutions[0]} | grep -q "/$framerate"; then
            framerate_found=true
            break
        fi
    done
    if [ "$framerate_found" = false ]; then
        log_error "device.framerate"
        return 1
    fi
    
    return 0
}

# Test video streaming
test_streaming() {
    log_info "Testing video streaming"
    
    local device=$(ls $(get_config_value "$CONFIG_FILE" ".video.devices.path") | head -n1)
    local test_duration=5
    
    # Test video capture
    if ! timeout $test_duration gst-launch-1.0 v4l2src device="$device" ! fakesink >/dev/null 2>&1; then
        log_error "test.capture"
        return 1
    fi
    
    # Test RTSP streaming
    local rtsp_port=$(get_config_value "$CONFIG_FILE" ".docker.components[0].ports[0]" | cut -d: -f1)
    if ! nc -z localhost "$rtsp_port"; then
        log_error "test.streaming"
        return 1
    fi
    
    # Test streaming performance
    local target_fps=$(get_config_value "$CONFIG_FILE" ".video.framerates[0]")
    local actual_fps=$(v4l2-ctl --device="$device" --get-fps)
    if [ "$actual_fps" -lt "$target_fps" ]; then
        log_error "test.performance" "$actual_fps" "$target_fps"
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
    
    # Check container privileges
    if ! docker inspect "$component" | grep -q '"Privileged": true'; then
        log_error "docker.privileged"
        return 1
    fi
    
    # Check device access
    local device=$(ls $(get_config_value "$CONFIG_FILE" ".video.devices.path") | head -n1)
    if ! docker exec "$component" test -e "$device"; then
        log_error "docker.device"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting video deployment tests"
    
    # Initialize progress tracking
    init_progress 5
    
    # Run tests
    update_progress "Testing package installation"
    if ! test_packages; then
        return 1
    fi
    
    update_progress "Testing video hardware"
    if ! test_hardware; then
        return 1
    fi
    
    update_progress "Testing video formats"
    if ! test_formats; then
        return 1
    fi
    
    update_progress "Testing video streaming"
    if ! test_streaming; then
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
