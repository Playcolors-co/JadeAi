#!/bin/bash

# Version declaration
JADE_PORTAINER_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"
REQUIRED_SYSTEM_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize logging
init_logging "portainer"

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
CONFIG_FILE=$(load_config "portainer")
if [ $? -ne 0 ]; then
    handle_error "Failed to load portainer configuration" "Configuration file could not be loaded" true
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "prerequisites.checking"
    
    # Check if system component is deployed
    if [ ! -f "/opt/control-panel/.system_setup_complete" ]; then
        handle_error "System component not deployed" "System setup completion marker not found" true
        return 1
    fi
    
    # Check system version
    local system_version=$(get_config_value "$(load_config "system")" ".version")
    if ! check_version "$system_version" "$REQUIRED_SYSTEM_VERSION"; then
        handle_error "System version incompatible" "Required: $REQUIRED_SYSTEM_VERSION, Current: $system_version" true
        return 1
    fi
    
    # Check Docker socket
    if [ ! -S "/var/run/docker.sock" ]; then
        handle_error "Docker socket not found" "Docker socket /var/run/docker.sock is not accessible" true
        return 1
    fi
    
    log_info "prerequisites.passed"
    return 0
}

# Function to create required directories
create_directories() {
    log_info "directories.creating"
    
    # Get directories from config
    local directories=($(get_config_value "$CONFIG_FILE" ".directories[].path"))
    local modes=($(get_config_value "$CONFIG_FILE" ".directories[].mode"))
    
    # Create each directory with proper permissions
    local i=0
    for dir in "${directories[@]}"; do
        sudo mkdir -p "$dir"
        sudo chmod "${modes[$i]}" "$dir"
        ((i++))
    done
    
    log_info "directories.complete"
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
        local output
        if ! output=$(DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>&1); then
            handle_error "Failed to install package" "Package: $pkg\n$output" true
            return 1
        fi
    done
    
    log_info "packages.complete"
    return 0
}

# Function to configure Nginx
configure_nginx() {
    log_info "nginx.configuring"
    
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.config_file")
    local server_name=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.server_name")
    local port=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.port")
    local ssl_enabled=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.ssl.enabled")

    # Create required directories
    sudo mkdir -p /var/log/jade/portainer
    sudo chown -R www-data:www-data /var/log/jade/portainer
    sudo chmod 755 /var/log/jade/portainer
    
    # Create Nginx configuration directory
    sudo mkdir -p "$(dirname "$nginx_file")"
    
    # Check if port 80 is in use and kill the process
    if netstat -tuln | grep -q ":80 "; then
        log_info "Stopping process using port 80"
        sudo fuser -k 80/tcp || true
    fi
    
    # Create Nginx configuration
    local output
    if ! output=$(cat > "$nginx_file" << EOF
server {
    listen 80;
    server_name ${server_name};
    
    access_log /var/log/jade/portainer/access.log;
    error_log /var/log/jade/portainer/error.log;
    
    location / {
        proxy_pass http://localhost:9000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    2>&1); then
        handle_error "Failed to create Nginx configuration" "File: $nginx_file\n$output" true
        return 1
    fi
    
    # Enable site
    local output
    if ! output=$(ln -sf "$nginx_file" "/etc/nginx/sites-enabled/" 2>&1); then
        handle_error "Failed to enable Nginx site" "Source: $nginx_file\n$output" true
        return 1
    fi
    
    # Configure SSL if enabled
    if [ "$ssl_enabled" = "true" ]; then
        log_info "ssl.configuring"
        if ! certbot --nginx -d "$server_name" --non-interactive --agree-tos --register-unsafely-without-email; then
            log_error "ssl.generate"
            return 1
        fi
        log_info "ssl.complete"
    fi
    
    # Test configuration
    local output
    if ! output=$(nginx -t 2>&1); then
        handle_error "Nginx configuration test failed" "$output" true
        return 1
    fi
    
    # Restart Nginx
    log_info "nginx.starting"
    local output
    if ! output=$(systemctl restart nginx 2>&1); then
        handle_error "Failed to restart Nginx" "$output" true
        return 1
    fi
    
    log_info "nginx.complete"
    return 0
}

# Function to configure Portainer templates
configure_templates() {
    log_info "portainer.templates"
    
    local template_file=$(get_config_value "$CONFIG_FILE" ".portainer.settings.template_file")
    local templates=($(get_config_value "$CONFIG_FILE" ".portainer.templates[]"))

    # Create template directory
    sudo mkdir -p "$(dirname "$template_file")"
    
    # Create templates configuration
    local output
    if ! output=$(cat > "$template_file" << EOF
{
  "version": "2",
  "templates": [
    {
      "title": "Jade System",
      "description": "Jade System Management Container",
      "image": "jade-system:1.0.0",
      "category": "Jade"
    },
    {
      "title": "Jade Bluetooth",
      "description": "Jade Bluetooth Management Container",
      "image": "jade-bluetooth:1.0.0",
      "category": "Jade"
    },
    {
      "title": "Jade Video",
      "description": "Jade Video Management Container",
      "image": "jade-video:1.0.0",
      "category": "Jade"
    },
    {
      "title": "Jade HID",
      "description": "Jade HID Management Container",
      "image": "jade-hid:1.0.0",
      "category": "Jade"
    },
    {
      "title": "Jade WiFi",
      "description": "Jade WiFi Management Container",
      "image": "jade-wifi:1.0.0",
      "category": "Jade"
    },
    {
      "title": "Jade Web Admin",
      "description": "Jade Web Administration Interface",
      "image": "jade-web-admin:1.0.0",
      "category": "Jade"
    }
  ]
}
EOF
    2>&1); then
        handle_error "Failed to create Portainer templates" "File: $template_file\n$output" true
        return 1
    fi
    
    return 0
}

# Function to setup Docker container
setup_docker() {
    log_info "docker.setup"
    
    local component="portainer"
    
    # Check if container exists and remove it
    if docker ps -a | grep -q "$component"; then
        local output
        if ! output=$(docker rm -f "$component" 2>&1); then
            handle_error "Failed to remove existing container" "Container: $component\n$output" true
            return 1
        fi
    fi

    # Check if port 9000 is in use and kill the process
    if netstat -tuln | grep -q ":9000 "; then
        log_info "Stopping process using port 9000"
        sudo fuser -k 9000/tcp || true
    fi
    
    # Start container with Docker socket mount
    log_info "docker.starting"
    local output
    if ! output=$(docker run -d \
        --name "$component" \
        --restart unless-stopped \
        -p 9000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        portainer/portainer-ce:latest 2>&1); then
        handle_error "Failed to start Portainer container" "Container: $component\n$output" true
        return 1
    fi
    
    log_info "docker.complete"
    return 0
}

# Function to test Portainer setup
test_portainer() {
    log_info "testing"
    
    # Run post-deployment tests
    local output
    if ! output=$(run_tests "portainer" "deploy" 2>&1); then
        handle_error "Portainer tests failed" "$output" true
        return 1
    fi
    
    log_info "tests_passed"
    return 0
}

# Function to rollback changes
rollback_portainer() {
    log_info "deployment.rollback"
    
    # Stop Docker container
    local component="portainer"
    if ! stop_docker_component "$component"; then
        log_warn "docker.start"
    fi
    
    # Stop Nginx
    systemctl stop nginx || true
    
    # Remove configurations
    local nginx_file=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.config_file")
    rm -f "$nginx_file" "/etc/nginx/sites-enabled/$(basename "$nginx_file")"
    
    # Remove SSL certificates if they exist
    local server_name=$(get_config_value "$CONFIG_FILE" ".portainer.nginx.server_name")
    certbot delete --cert-name "$server_name" --non-interactive || true
    
    # Remove templates
    local template_file=$(get_config_value "$CONFIG_FILE" ".portainer.settings.template_file")
    rm -f "$template_file"
    
    # Update deployment status
    update_deployment_status "portainer" "rolled_back" "$JADE_PORTAINER_VERSION"
    
    # Run rollback tests
    if ! run_tests "portainer" "rollback"; then
        log_error "test.failed"
        return 1
    fi
    
    return 0
}

# Main setup function
setup_portainer() {
    log_info "setup_start"
    
    # Initialize progress tracking
    init_progress 7
    
    # Check prerequisites
    update_progress "Checking prerequisites"
    if ! check_prerequisites; then
        return 1
    fi
    
    # Create required directories
    update_progress "Creating required directories"
    if ! create_directories; then
        return 1
    fi

    # Create backup if already deployed
    update_progress "Creating backup"
    local status=$(get_deployment_status "portainer")
    if [ "$status" != "not_deployed" ]; then
        local backup_location=$(get_config_value "$CONFIG_FILE" ".deployment.backup.location")
        create_backup "portainer" "$backup_location"
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
    
    # Configure templates
    update_progress "Configuring templates"
    if ! configure_templates; then
        return 1
    fi
    
    # Setup Docker container
    update_progress "Setting up Docker container"
    if ! setup_docker; then
        return 1
    fi
    
    # Test the setup
    update_progress "Running Portainer tests"
    if ! test_portainer; then
        return 1
    fi
    
    # Update deployment status
    update_deployment_status "portainer" "deployed" "$JADE_PORTAINER_VERSION"
    
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
                if ! rollback_portainer; then
                    exit 1
                fi
                exit 0
                ;;
            --check)
                status=$(get_deployment_status "portainer")
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
    if ! setup_portainer; then
        log_error "Setup failed"
        exit 1
    fi
fi
