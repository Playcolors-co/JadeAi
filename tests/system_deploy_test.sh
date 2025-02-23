#!/bin/bash

# Version declaration
JADE_SYSTEM_TEST_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    log_error "test.version_mismatch" "$REQUIRED_COMMON_VERSION" "$JADE_COMMON_VERSION"
    exit 1
fi

# Initialize logging
init_logging "system_test"

# Load configuration
CONFIG_FILE=$(load_config "system")
if [ $? -ne 0 ]; then
    log_error "test.config_load_failed"
    exit 1
fi

# Test required packages
test_packages() {
    log_info "test.packages.checking"
    
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    for pkg in "${packages[@]}"; do
        log_info "test.packages.checking_specific" "$pkg"
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_error "test.packages.not_installed" "$pkg"
            return 1
        fi
        
        # Check version if specified
        local required_version=$(get_config_value "$CONFIG_FILE" ".packages[] | select(.name==\"$pkg\") | .version")
        if [ "$required_version" != "latest" ]; then
            local installed_version=$(dpkg -l "$pkg" | awk '/^ii/ {print $3}')
            if ! check_version "$installed_version" "$required_version"; then
                log_error "test.packages.version_mismatch" "$pkg" "$required_version" "$installed_version"
                return 1
            fi
        fi
    done
    
    log_info "test.packages.success"
    return 0
}

# Test required directories
test_directories() {
    log_info "test.directories.checking"
    
    local dirs=($(get_config_value "$CONFIG_FILE" ".directories[].path"))
    local modes=($(get_config_value "$CONFIG_FILE" ".directories[].mode"))
    local owners=($(get_config_value "$CONFIG_FILE" ".directories[].owner"))
    local groups=($(get_config_value "$CONFIG_FILE" ".directories[].group"))
    
    for i in "${!dirs[@]}"; do
        local dir="${dirs[$i]}"
        local mode="${modes[$i]}"
        local owner="${owners[$i]}"
        local group="${groups[$i]}"
        
        log_info "test.directories.checking_specific" "$dir"
        
        if [ ! -d "$dir" ]; then
            log_error "test.directories.not_found" "$dir"
            return 1
        fi
        
        local actual_mode=$(stat -c "%a" "$dir")
        if [ "$actual_mode" != "$mode" ]; then
            log_error "test.directories.wrong_permissions" "$dir" "$mode" "$actual_mode"
            return 1
        fi
        
        local actual_owner=$(stat -c "%U" "$dir")
        if [ "$actual_owner" != "$owner" ]; then
            log_error "test.directories.wrong_owner" "$dir" "$owner" "$actual_owner"
            return 1
        fi
        
        local actual_group=$(stat -c "%G" "$dir")
        if [ "$actual_group" != "$group" ]; then
            log_error "test.directories.wrong_group" "$dir" "$group" "$actual_group"
            return 1
        fi
    done
    
    log_info "test.directories.success"
    return 0
}

# Test Docker setup
test_docker() {
    log_info "test.docker.checking"
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log_error "test.docker.not_running"
        return 1
    fi
    
    # Check Docker version
    local required_version=$(get_config_value "$CONFIG_FILE" ".required_versions.docker")
    local current_version=$(docker version --format '{{.Server.Version}}')
    if ! check_version "$current_version" "$required_version"; then
        log_error "test.docker.version_mismatch" "$required_version" "$current_version"
        return 1
    fi
    
    # Check Docker network
    local network=$(get_config_value "$CONFIG_FILE" ".docker.network")
    if ! docker network inspect "$network" >/dev/null 2>&1; then
        log_error "test.docker.network_missing" "$network"
        return 1
    fi
    
    # Check network configuration
    local subnet=$(get_config_value "$CONFIG_FILE" ".docker.network_config.subnet")
    local driver=$(get_config_value "$CONFIG_FILE" ".docker.network_config.driver")
    local network_info=$(docker network inspect "$network")
    
    if ! echo "$network_info" | jq -e --arg subnet "$subnet" '.[] | select(.IPAM.Config[].Subnet == $subnet)' >/dev/null; then
        log_error "test.docker.wrong_subnet" "$network" "$subnet"
        return 1
    fi
    
    if ! echo "$network_info" | jq -e --arg driver "$driver" '.[] | select(.Driver == $driver)' >/dev/null; then
        log_error "test.docker.wrong_driver" "$network" "$driver"
        return 1
    fi
    
    log_info "test.docker.success"
    return 0
}

# Test system configuration
test_configuration() {
    log_info "test.config.checking"
    
    # Check status file
    local status_file=$(get_config_value "$CONFIG_FILE" ".status.file")
    if [ ! -f "$status_file" ]; then
        log_error "test.config.status_missing" "$status_file"
        return 1
    fi
    
    # Check status file permissions
    local status_mode=$(get_config_value "$CONFIG_FILE" ".status.mode")
    local actual_mode=$(stat -c "%a" "$status_file")
    if [ "$actual_mode" != "$status_mode" ]; then
        log_error "test.config.wrong_permissions" "$status_file" "$status_mode" "$actual_mode"
        return 1
    fi
    
    # Check deployment status
    local status=$(get_deployment_status "system")
    if [ "$status" != "deployed" ]; then
        log_error "test.config.wrong_status" "$status"
        return 1
    fi
    
    log_info "test.config.success"
    return 0
}

# Test health checks
test_health() {
    log_info "test.health.checking"
    
    local endpoint=$(get_config_value "$CONFIG_FILE" ".deployment.post_deploy.health_check.endpoint")
    local timeout=$(get_config_value "$CONFIG_FILE" ".deployment.post_deploy.health_check.timeout")
    local retries=$(get_config_value "$CONFIG_FILE" ".deployment.post_deploy.health_check.retries")
    
    local retry_count=0
    while [ $retry_count -lt $retries ]; do
        if curl -s -f -m "$timeout" "$endpoint" >/dev/null 2>&1; then
            log_info "test.health.success"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $retries ]; then
            log_warn "test.health.retry" "$retry_count" "$retries"
            sleep 5
        fi
    done
    
    log_error "test.health.failed" "$endpoint"
    return 1
}

# Main test execution
main() {
    log_info "test.start"
    
    # Initialize progress tracking
    init_progress 5
    
    # Run tests
    update_progress "Testing package installation"
    if ! test_packages; then
        return 1
    fi
    
    update_progress "Testing directory structure"
    if ! test_directories; then
        return 1
    fi
    
    update_progress "Testing Docker setup"
    if ! test_docker; then
        return 1
    fi
    
    update_progress "Testing system configuration"
    if ! test_configuration; then
        return 1
    fi
    
    update_progress "Testing system health"
    if ! test_health; then
        return 1
    fi
    
    log_info "test.success"
    return 0
}

# Set up error handling
setup_error_handling

# Run tests
if ! main; then
    log_error "test.failed"
    exit 1
fi

exit 0
