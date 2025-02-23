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
init_logging "system_rollback_test"

# Load configuration
CONFIG_FILE=$(load_config "system")
if [ $? -ne 0 ]; then
    log_error "test.config_load_failed"
    exit 1
fi

# Test package removal
test_packages_removed() {
    log_info "test.rollback.packages.checking"
    
    local packages=($(get_config_value "$CONFIG_FILE" ".packages[].name"))
    for pkg in "${packages[@]}"; do
        # Only check packages marked as required
        local required=$(get_config_value "$CONFIG_FILE" ".packages[] | select(.name==\"$pkg\") | .required")
        if [ "$required" = "true" ]; then
            log_info "test.rollback.packages.checking_specific" "$pkg"
            if dpkg -l | grep -q "^ii  $pkg "; then
                log_error "test.rollback.packages.still_installed" "$pkg"
                return 1
            fi
        fi
    done
    
    log_info "test.rollback.packages.success"
    return 0
}

# Test directory cleanup
test_directories_cleaned() {
    log_info "test.rollback.directories.checking"
    
    local dirs=($(get_config_value "$CONFIG_FILE" ".directories[].path"))
    for dir in "${dirs[@]}"; do
        log_info "test.rollback.directories.checking_specific" "$dir"
        if [ -d "$dir" ] && [ ! -z "$(ls -A "$dir")" ]; then
            log_error "test.rollback.directories.not_empty" "$dir"
            return 1
        fi
    done
    
    log_info "test.rollback.directories.success"
    return 0
}

# Test Docker cleanup
test_docker_cleanup() {
    log_info "test.rollback.docker.checking"
    
    # Check Docker containers
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    if docker ps -a | grep -q "$component"; then
        log_error "test.rollback.docker.container_exists" "$component"
        return 1
    fi
    
    # Check Docker images
    local image=$(get_config_value "$CONFIG_FILE" ".docker.components[0].image" | sed "s/\${version}/$JADE_SYSTEM_VERSION/")
    if docker images | grep -q "$image"; then
        log_error "test.rollback.docker.image_exists" "$image"
        return 1
    fi
    
    # Check Docker network removed
    local network=$(get_config_value "$CONFIG_FILE" ".docker.network")
    if docker network ls | grep -q "$network"; then
        log_error "test.rollback.docker.network_exists" "$network"
        return 1
    fi
    
    log_info "test.rollback.docker.success"
    return 0
}

# Test configuration cleanup
test_configuration_cleanup() {
    log_info "test.rollback.config.checking"
    
    # Check status file removed
    local status_file=$(get_config_value "$CONFIG_FILE" ".status.file")
    if [ -f "$status_file" ]; then
        log_error "test.rollback.config.status_exists" "$status_file"
        return 1
    fi
    
    # Check deployment status
    local status=$(get_deployment_status "system")
    if [ "$status" = "deployed" ]; then
        log_error "test.rollback.config.wrong_status" "$status"
        return 1
    fi
    
    log_info "test.rollback.config.success"
    return 0
}

# Test backup creation
test_backup() {
    log_info "test.rollback.backup.checking"
    
    local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
    if [ ! -d "$backup_location" ]; then
        log_error "test.rollback.backup.dir_missing" "$backup_location"
        return 1
    fi
    
    # Check if at least one backup exists
    if [ -z "$(ls -A "$backup_location")" ]; then
        log_error "test.rollback.backup.empty" "$backup_location"
        return 1
    fi
    
    # Check backup contents
    local latest_backup=$(ls -t "$backup_location" | head -n1)
    local backup_path="$backup_location/$latest_backup"
    
    # Check backup structure
    local required_files=("config" "scripts" "docker-compose.yml")
    for file in "${required_files[@]}"; do
        if [ ! -e "$backup_path/$file" ]; then
            log_error "test.rollback.backup.missing_file" "$file" "$backup_path"
            return 1
        fi
    done
    
    log_info "test.rollback.backup.success"
    return 0
}

# Main test execution
main() {
    log_info "test.rollback.start"
    
    # Initialize progress tracking
    init_progress 5
    
    # Run tests
    update_progress "Testing package removal"
    if ! test_packages_removed; then
        return 1
    fi
    
    update_progress "Testing directory cleanup"
    if ! test_directories_cleaned; then
        return 1
    fi
    
    update_progress "Testing Docker cleanup"
    if ! test_docker_cleanup; then
        return 1
    fi
    
    update_progress "Testing configuration cleanup"
    if ! test_configuration_cleanup; then
        return 1
    fi
    
    update_progress "Testing backup creation"
    if ! test_backup; then
        return 1
    fi
    
    log_info "test.rollback.success"
    return 0
}

# Set up error handling
setup_error_handling

# Run tests
if ! main; then
    log_error "test.rollback.failed"
    exit 1
fi

exit 0
