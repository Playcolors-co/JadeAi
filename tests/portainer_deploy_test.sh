#!/bin/bash

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# Initialize logging
init_logging "portainer_test"

# Load configuration
CONFIG_FILE=$(load_config "portainer")
if [ $? -ne 0 ]; then
    log_error "Failed to load portainer configuration"
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
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.config_file")
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
    
    local ssl_enabled=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.ssl.enabled")
    if [ "$ssl_enabled" = "true" ]; then
        local server_name=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.server_name")
        local cert_path=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.ssl.cert_path")
        local key_path=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.ssl.key_path")
        
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

# Test Portainer templates
test_templates() {
    log_info "Testing Portainer templates"
    
    local template_file=$(get_config_value "$CONFIG_FILE" ".portainer.settings.template_file")
    
    # Check template file
    if [ ! -f "$template_file" ]; then
        log_error "portainer.templates"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq . "$template_file" >/dev/null 2>&1; then
        log_error "portainer.templates"
        return 1
    fi
    
    # Check template version
    if ! jq -e '.version == "2"' "$template_file" >/dev/null; then
        log_error "portainer.templates"
        return 1
    fi
    
    # Check required templates
    if ! jq -e '.templates | length > 0' "$template_file" >/dev/null; then
        log_error "test.templates" "No templates found"
        return 1
    fi
    
    # Check template structure
    if ! jq -e '.templates[] | select(.title and .description and .image and .category)' "$template_file" >/dev/null; then
        log_error "test.templates" "Invalid template structure"
        return 1
    fi
    
    return 0
}

# Test Portainer API
test_api() {
    log_info "Testing Portainer API"
    
    local port=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.port")
    local wait_time=30
    local retry_interval=5
    local elapsed=0
    
    # Wait for API to be ready
    while [ $elapsed -lt $wait_time ]; do
        if curl -s "http://localhost:$port/api/status" >/dev/null; then
            break
        fi
        sleep $retry_interval
        elapsed=$((elapsed + retry_interval))
    done
    
    if [ $elapsed -ge $wait_time ]; then
        log_error "test.api" "API not responding"
        return 1
    fi
    
    # Test API endpoints
    local endpoints=(
        "/api/status"
        "/api/endpoints"
        "/api/templates"
    )
    
    for endpoint in "${endpoints[@]}"; do
        # Test response time
        local start_time=$(date +%s%N)
        if ! curl -s "http://localhost:$port$endpoint" >/dev/null; then
            log_error "test.api" "$endpoint"
            return 1
        fi
        local end_time=$(date +%s%N)
        local response_time=$(( ($end_time - $start_time) / 1000000 ))
        
        if [ $response_time -gt 1000 ]; then
            log_error "test.performance" "$response_time" "1000"
            return 1
        fi
    done
    
    return 0
}

# Test Docker endpoint
test_docker_endpoint() {
    log_info "Testing Docker endpoint"
    
    local endpoint_url=$(get_config_value "$CONFIG_FILE" ".portainer.endpoint_url")
    
    # Check Docker socket
    if [ ! -S "/var/run/docker.sock" ]; then
        log_error "portainer.access"
        return 1
    fi
    
    # Check socket permissions
    local perms=$(stat -c "%a" "/var/run/docker.sock")
    if [ "$perms" != "660" ]; then
        log_error "portainer.access"
        return 1
    fi
    
    # Test Docker API
    if ! curl -s --unix-socket /var/run/docker.sock http://localhost/version >/dev/null; then
        log_error "portainer.endpoint"
        return 1
    fi
    
    return 0
}

# Test Docker container
test_docker() {
    log_info "Testing Docker container"
    
    local component="portainer"
    
    # Print container info before testing
    echo "Current containers:"
    docker ps -a
    echo "Container logs:"
    docker logs "$component" || true
    
    # Check if container is running
    if ! docker ps | grep -q "$component"; then
        log_error "docker.start"
        return 1
    fi
    
    # Check container logs for critical errors
    if docker logs "$component" 2>&1 | grep -i "fatal\|panic\|critical error"; then
        log_error "docker.start"
        return 1
    fi
    
    # Give container time to start
    sleep 5
    
    # Check container health
    local status=$(docker inspect -f '{{.State.Status}}' "$component")
    if [ "$status" != "running" ]; then
        log_error "docker.start"
        echo "Container status: $status"
        echo "Container logs:"
        docker logs "$component"
        echo "Container inspect:"
        docker inspect "$component"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting Portainer deployment tests"
    
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
    
    update_progress "Testing Portainer templates"
    if ! test_templates; then
        return 1
    fi
    
    update_progress "Testing Portainer API"
    if ! test_api; then
        return 1
    fi
    
    update_progress "Testing Docker endpoint"
    if ! test_docker_endpoint; then
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
