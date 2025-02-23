#!/bin/bash

# Version declaration
JADE_WEB_ADMIN_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"
REQUIRED_SYSTEM_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize logging
init_logging "web_admin"

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    log_error "prerequisites.version" "$REQUIRED_COMMON_VERSION" "$JADE_COMMON_VERSION"
    exit 1
fi

# Load configuration
CONFIG_FILE=$(load_config "web_admin")
if [ $? -ne 0 ]; then
    log_error "Failed to load web admin configuration"
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

# Function to configure Nginx
configure_nginx() {
    log_info "nginx.configuring"
    
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".web.nginx.config_file")
    local server_name=$(get_config_value "$CONFIG_FILE" ".web.nginx.server_name")
    local port=$(get_config_value "$CONFIG_FILE" ".web.nginx.port")
    local ssl_enabled=$(get_config_value "$CONFIG_FILE" ".web.nginx.ssl.enabled")
    
    # Create Nginx configuration
    cat > "$nginx_file" << EOF
server {
    listen ${port};
    server_name ${server_name};
    
    access_log /var/log/jade/web-admin/access.log;
    error_log /var/log/jade/web-admin/error.log;
    
    location / {
        proxy_pass http://unix:/run/jade-admin.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    
    location /api {
        proxy_pass http://127.0.0.1:$(get_config_value "$CONFIG_FILE" ".web.api.port");
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    
    if [ $? -ne 0 ]; then
        log_error "nginx.config"
        return 1
    fi
    
    # Enable site
    if ! ln -sf "$nginx_file" "/etc/nginx/sites-enabled/"; then
        log_error "nginx.site"
        return 1
    fi
    
    # Configure SSL if enabled
    if [ "$ssl_enabled" = "true" ]; then
        log_info "ssl.configuring"
        if ! certbot --nginx -d "$server_name" --non-interactive --agree-tos; then
            log_error "ssl.generate"
            return 1
        fi
        log_info "ssl.complete"
    fi
    
    # Test configuration
    if ! nginx -t; then
        log_error "nginx.config"
        return 1
    fi
    
    # Restart Nginx
    log_info "nginx.starting"
    if ! systemctl restart nginx; then
        log_error "nginx.start"
        return 1
    fi
    
    log_info "nginx.complete"
    return 0
}

# Function to configure Gunicorn
configure_gunicorn() {
    log_info "gunicorn.configuring"
    
    local workers=$(get_config_value "$CONFIG_FILE" ".web.gunicorn.workers")
    local bind=$(get_config_value "$CONFIG_FILE" ".web.gunicorn.bind")
    local timeout=$(get_config_value "$CONFIG_FILE" ".web.gunicorn.timeout")
    
    # Create Gunicorn service
    cat > "/etc/systemd/system/jade-admin.service" << EOF
[Unit]
Description=Jade Admin Gunicorn Service
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/jade-admin
ExecStart=/usr/bin/gunicorn --workers ${workers} --bind ${bind} --timeout ${timeout} app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    if [ $? -ne 0 ]; then
        log_error "gunicorn.config"
        return 1
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    # Start service
    log_info "gunicorn.starting"
    if ! systemctl enable --now jade-admin; then
        log_error "gunicorn.start"
        return 1
    fi
    
    log_info "gunicorn.complete"
    return 0
}

# Function to configure API
configure_api() {
    log_info "api.configuring"
    
    local api_port=$(get_config_value "$CONFIG_FILE" ".web.api.port")
    local endpoints=($(get_config_value "$CONFIG_FILE" ".web.api.endpoints[].path"))
    
    # Create API configuration
    cat > "/etc/jade/web-admin/api.yaml" << EOF
port: ${api_port}
endpoints:
$(for endpoint in "${endpoints[@]}"; do echo "  - $endpoint"; done)
EOF
    
    if [ $? -ne 0 ]; then
        log_error "api.endpoint"
        return 1
    fi
    
    # Start API service
    log_info "api.starting"
    if ! systemctl restart jade-admin; then
        log_error "api.start"
        return 1
    fi
    
    log_info "api.complete"
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

# Function to test web admin setup
test_web_admin() {
    log_info "testing"
    
    # Run post-deployment tests
    if ! run_tests "web_admin" "deploy"; then
        log_error "test.failed"
        return 1
    fi
    
    log_info "tests_passed"
    return 0
}

# Function to rollback changes
rollback_web_admin() {
    log_info "deployment.rollback"
    
    # Stop Docker container
    local component=$(get_config_value "$CONFIG_FILE" ".docker.components[0].name")
    if ! stop_docker_component "$component"; then
        log_warn "docker.start"
    fi
    
    # Stop services
    systemctl stop nginx jade-admin || true
    
    # Remove configurations
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".web.nginx.config_file")
    rm -f "$nginx_file" "/etc/nginx/sites-enabled/$(basename "$nginx_file")"
    rm -f "/etc/systemd/system/jade-admin.service"
    rm -f "/etc/jade/web-admin/api.yaml"
    
    # Remove SSL certificates if they exist
    local server_name=$(get_config_value "$CONFIG_FILE" ".web.nginx.server_name")
    certbot delete --cert-name "$server_name" --non-interactive || true
    
    # Update deployment status
    update_deployment_status "web_admin" "rolled_back" "$JADE_WEB_ADMIN_VERSION"
    
    # Run rollback tests
    if ! run_tests "web_admin" "rollback"; then
        log_error "test.failed"
        return 1
    fi
    
    return 0
}

# Main setup function
setup_web_admin() {
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
    local status=$(get_deployment_status "web_admin")
    if [ "$status" != "not_deployed" ]; then
        local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        create_backup "web_admin" "$backup_location"
    fi
    
    # Install required packages
    update_progress "Installing required packages"
    if ! install_packages; then
        return 1
    fi
    
    # Configure Nginx
    update_progress "Configuring Nginx"
    if ! configure_nginx; then
        return 1
    fi
    
    # Configure Gunicorn
    update_progress "Configuring Gunicorn"
    if ! configure_gunicorn; then
        return 1
    fi
    
    # Configure API
    update_progress "Configuring API"
    if ! configure_api; then
        return 1
    fi
    
    # Setup Docker container
    update_progress "Setting up Docker container"
    if ! setup_docker; then
        return 1
    fi
    
    # Test the setup
    update_progress "Running Web Admin tests"
    if ! test_web_admin; then
        return 1
    fi
    
    # Update deployment status
    update_deployment_status "web_admin" "deployed" "$JADE_WEB_ADMIN_VERSION"
    
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
                if ! rollback_web_admin; then
                    exit 1
                fi
                exit 0
                ;;
            --check)
                status=$(get_deployment_status "web_admin")
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
    if ! setup_web_admin; then
        log_error "Setup failed"
        exit 1
    fi
fi
