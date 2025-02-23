#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "web_admin_test"

# Load configuration
CONFIG_FILE=$(load_config "web_admin")
if [ $? -ne 0 ]; then
    log_error "Failed to load web admin configuration"
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

# Test Nginx configuration
test_nginx() {
    log_info "Testing Nginx configuration"
    
    # Check Nginx service
    if ! systemctl is-active --quiet nginx; then
        log_error "nginx.start"
        return 1
    fi
    
    # Check configuration file
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".web.nginx.config_file")
    if [ ! -f "$nginx_file" ]; then
        log_error "nginx.config"
        return 1
    fi
    
    # Check site enabled
    if [ ! -L "/etc/nginx/sites-enabled/$(basename "$nginx_file")" ]; then
        log_error "nginx.site"
        return 1
    fi
    
    # Test configuration syntax
    if ! nginx -t; then
        log_error "nginx.config"
        return 1
    fi
    
    return 0
}

# Test SSL configuration
test_ssl() {
    log_info "Testing SSL configuration"
    
    local ssl_enabled=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.enabled")
    if [ "$ssl_enabled" = "true" ]; then
        local server_name=$(get_config_value "$CONFIG_FILE" ".web.nginx.server_name")
        local cert_path=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.cert_path")
        local key_path=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.key_path")
        
        # Check certificate files
        if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
            log_error "ssl.install"
            return 1
        fi
        
        # Verify certificate
        if ! openssl x509 -in "$cert_path" -text -noout >/dev/null 2>&1; then
            log_error "ssl.verify"
            return 1
        fi
        
        # Check certificate chain
        if ! openssl verify "$cert_path" >/dev/null 2>&1; then
            log_error "ssl.chain"
            return 1
        fi
        
        # Check expiry
        local expiry_days=$(openssl x509 -in "$cert_path" -enddate -noout | cut -d= -f2 | xargs -I{} date -d "{}" +%s)
        local current_time=$(date +%s)
        local days_left=$(( ($expiry_days - $current_time) / 86400 ))
        if [ $days_left -lt 30 ]; then
            log_warn "ssl.expiring" "$server_name" "$days_left"
        fi
    fi
    
    return 0
}

# Test Gunicorn configuration
test_gunicorn() {
    log_info "Testing Gunicorn configuration"
    
    # Check service file
    if [ ! -f "/etc/systemd/system/jade-admin.service" ]; then
        log_error "gunicorn.config"
        return 1
    fi
    
    # Check service status
    if ! systemctl is-active --quiet jade-admin; then
        log_error "gunicorn.start"
        return 1
    fi
    
    # Check Unix socket
    local bind=$(get_config_value "$CONFIG_FILE" ".web.gunicorn.bind")
    local socket_path=$(echo "$bind" | cut -d: -f2)
    if [ ! -S "$socket_path" ]; then
        log_error "gunicorn.socket"
        return 1
    fi
    
    return 0
}

# Test API endpoints
test_api() {
    log_info "Testing API endpoints"
    
    local api_port=$(get_config_value "$CONFIG_FILE" ".web.api.port")
    local endpoints=($(get_config_value "$CONFIG_FILE" ".web.api.endpoints[].path"))
    
    # Wait for API to be ready
    sleep 2
    
    # Test each endpoint
    for endpoint in "${endpoints[@]}"; do
        # Test GET request
        if ! curl -s -f "http://localhost:$api_port$endpoint" >/dev/null; then
            log_error "api.endpoint" "$endpoint"
            return 1
        fi
        
        # Test response time
        local start_time=$(date +%s%N)
        curl -s -f "http://localhost:$api_port$endpoint" >/dev/null
        local end_time=$(date +%s%N)
        local response_time=$(( ($end_time - $start_time) / 1000000 ))
        
        if [ $response_time -gt 1000 ]; then
            log_error "test.performance" "$response_time" "1000"
            return 1
        fi
    done
    
    return 0
}

# Test HTTP/HTTPS access
test_web_access() {
    log_info "Testing web access"
    
    local port=$(get_config_value "$CONFIG_FILE" ".web.nginx.port")
    local server_name=$(get_config_value "$CONFIG_FILE" ".web.nginx.server_name")
    local ssl_enabled=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.enabled")
    
    # Test HTTP
    if ! curl -s -f "http://localhost:$port" >/dev/null; then
        log_error "test.http" "Connection failed"
        return 1
    fi
    
    # Test HTTPS if enabled
    if [ "$ssl_enabled" = "true" ]; then
        if ! curl -s -f -k "https://localhost:$port" >/dev/null; then
            log_error "test.https" "Connection failed"
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
    
    # Check volume mounts
    local volumes=($(get_config_value "$CONFIG_FILE" ".docker.components[0].volumes[]" | cut -d: -f1))
    for volume in "${volumes[@]}"; do
        if ! docker exec "$component" test -e "$volume"; then
            log_error "docker.volume"
            return 1
        fi
    done
    
    return 0
}

# Main test execution
main() {
    log_info "Starting Web Admin deployment tests"
    
    # Initialize progress tracking
    init_progress 7
    
    # Run tests
    update_progress "Testing package installation"
    if ! test_packages; then
        return 1
    fi
    
    update_progress "Testing Nginx configuration"
    if ! test_nginx; then
        return 1
    fi
    
    update_progress "Testing SSL configuration"
    if ! test_ssl; then
        return 1
    fi
    
    update_progress "Testing Gunicorn configuration"
    if ! test_gunicorn; then
        return 1
    fi
    
    update_progress "Testing API endpoints"
    if ! test_api; then
        return 1
    fi
    
    update_progress "Testing web access"
    if ! test_web_access; then
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
