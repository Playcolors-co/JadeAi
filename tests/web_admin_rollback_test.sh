#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "web_admin_rollback_test"

# Load configuration
CONFIG_FILE=$(load_config "web_admin")
if [ $? -ne 0 ]; then
    log_error "Failed to load web admin configuration"
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

# Test Nginx cleanup
test_nginx_cleanup() {
    log_info "Testing Nginx cleanup"
    
    # Check if site configuration is removed
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".web.nginx.config_file")
    if [ -f "$nginx_file" ]; then
        log_error "Nginx configuration still exists"
        return 1
    fi
    
    # Check if site is disabled
    if [ -L "/etc/nginx/sites-enabled/$(basename "$nginx_file")" ]; then
        log_error "Nginx site still enabled"
        return 1
    fi
    
    # Check if custom configurations are removed
    if grep -r "jade-admin" /etc/nginx/sites-available/ >/dev/null 2>&1; then
        log_error "Custom Nginx configurations still exist"
        return 1
    fi
    
    return 0
}

# Test SSL cleanup
test_ssl_cleanup() {
    log_info "Testing SSL cleanup"
    
    local ssl_enabled=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.enabled")
    if [ "$ssl_enabled" = "true" ]; then
        local server_name=$(get_config_value "$CONFIG_FILE" ".web.nginx.server_name")
        local cert_path=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.cert_path")
        local key_path=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.key_path")
        
        # Check if certificate files are removed
        if [ -f "$cert_path" ] || [ -f "$key_path" ]; then
            log_error "SSL certificates still exist"
            return 1
        fi
        
        # Check if certbot configuration is removed
        if [ -d "/etc/letsencrypt/live/$server_name" ]; then
            log_error "Certbot configuration still exists"
            return 1
        fi
    fi
    
    return 0
}

# Test Gunicorn cleanup
test_gunicorn_cleanup() {
    log_info "Testing Gunicorn cleanup"
    
    # Check if service file is removed
    if [ -f "/etc/systemd/system/jade-admin.service" ]; then
        log_error "Gunicorn service file still exists"
        return 1
    fi
    
    # Check if service is stopped
    if systemctl is-active --quiet jade-admin; then
        log_error "Gunicorn service still running"
        return 1
    fi
    
    # Check if socket is removed
    local bind=$(get_config_value "$CONFIG_FILE" ".web.gunicorn.bind")
    local socket_path=$(echo "$bind" | cut -d: -f2)
    if [ -S "$socket_path" ]; then
        log_error "Unix socket still exists"
        return 1
    fi
    
    return 0
}

# Test API cleanup
test_api_cleanup() {
    log_info "Testing API cleanup"
    
    # Check if API configuration is removed
    if [ -f "/etc/jade/web-admin/api.yaml" ]; then
        log_error "API configuration still exists"
        return 1
    fi
    
    # Check if API port is closed
    local api_port=$(get_config_value "$CONFIG_FILE" ".web.api.port")
    if nc -z localhost "$api_port" 2>/dev/null; then
        log_error "API port still open"
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
    local image=$(get_config_value "$CONFIG_FILE" ".docker.components[0].image" | sed "s/\${version}/$JADE_WEB_ADMIN_VERSION/")
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
    local status=$(get_deployment_status "web_admin")
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
    if [ ! -f "$backup_location/$latest_backup/nginx.conf" ]; then
        log_error "Backup missing Nginx configuration"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting Web Admin rollback tests"
    
    # Initialize progress tracking
    init_progress 9
    
    # Run tests
    update_progress "Testing package removal"
    if ! test_packages_removed; then
        return 1
    fi
    
    update_progress "Testing Nginx cleanup"
    if ! test_nginx_cleanup; then
        return 1
    fi
    
    update_progress "Testing SSL cleanup"
    if ! test_ssl_cleanup; then
        return 1
    fi
    
    update_progress "Testing Gunicorn cleanup"
    if ! test_gunicorn_cleanup; then
        return 1
    fi
    
    update_progress "Testing API cleanup"
    if ! test_api_cleanup; then
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
