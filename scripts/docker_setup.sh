#!/bin/bash

# Component information
COMPONENT_NAME="JadeDocker"
COMPONENT_VERSION="1.0.0"
REQUIRED_VERSION="1.0.0"

# Initialize paths from config
CONFIG_FILE="config/docker.yaml"
MESSAGES_FILE="config/messages_docker_en.json"

# Source common functions
source "$(dirname "$0")/common.sh"

# Initialize logging
init_logging "docker"

# Get message from locale file
get_message() {
    local key=$1
    shift
    local value
    value=$(jq -r ".$key" "$MESSAGES_FILE" 2>/dev/null)
    if [ "$value" = "null" ]; then
        echo "Message not found: $key"
    else
        # Replace parameters
        local i=0
        for param in "$@"; do
            value=${value//\{$i\}/$param}
            i=$((i + 1))
        done
        echo "$value"
    fi
}

# Load paths from config
load_paths() {
    BACKUP_DIR=$(yq eval '.deployment.backup_dir' "$CONFIG_FILE")
    STATUS_FILE=$(yq eval '.deployment.status_file' "$CONFIG_FILE")
    LOG_DIR=$(yq eval '.deployment.log_dir' "$CONFIG_FILE")
    
    # Create directories if they don't exist
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"
}

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

# Get OS codename from release info
get_os_codename() {
    local os_release_file="/etc/os-release"
    local codename=""
    
    if [ -f "$os_release_file" ]; then
        # Try VERSION_CODENAME first
        codename=$(grep "VERSION_CODENAME" "$os_release_file" | cut -d= -f2 | tr -d '"')
        
        # If VERSION_CODENAME is empty, try to extract from VERSION
        if [ -z "$codename" ]; then
            local version
            version=$(grep "VERSION=" "$os_release_file" | cut -d= -f2 | tr -d '"')
            # Extract codename from version string (e.g., "11 (bullseye)" -> "bullseye")
            codename=$(echo "$version" | grep -oP '\(\K[^)]+' || echo "")
        fi
        
        # If still empty, try to determine from VERSION_ID
        if [ -z "$codename" ]; then
            local version_id
            version_id=$(grep "VERSION_ID" "$os_release_file" | cut -d= -f2 | tr -d '"')
            case "$version_id" in
                "11") codename="bullseye" ;;
                "12") codename="bookworm" ;;
                "22.04") codename="jammy" ;;
                "20.04") codename="focal" ;;
                *) codename="" ;;
            esac
        fi
    fi
    
    echo "$codename"
}

# Detect OS and configure repository with enhanced error checking
configure_repository_url() {
    local output
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$(get_os_codename)
        
        # Verify we got a valid OS version
        if [ -z "$OS_VERSION" ]; then
            output=$(cat /etc/os-release)
            handle_error "Could not determine OS version codename" "$output" true
        fi
    else
        output=$(cat /etc/os-release)
        handle_error "Could not detect OS distribution" "$output" true
    fi
    
    # Set repository URL based on OS
    case $OS_NAME in
        debian|raspbian)
            REPO_URL="https://download.docker.com/linux/debian"
            ;;
        ubuntu)
            REPO_URL="https://download.docker.com/linux/ubuntu"
            ;;
        *)
            handle_error "Unsupported OS distribution: $OS_NAME" "Only Debian, Raspbian, and Ubuntu are supported" true
            ;;
    esac
    
    # Set architecture
    if [ "$(uname -m)" = "aarch64" ]; then
        ARCH="arm64"
    elif [ "$(uname -m)" = "armv7l" ]; then
        ARCH="armhf"
    else
        ARCH="$(dpkg --print-architecture)"
    fi
    
    # Debug output
    {
        echo "Full OS release information:"
        cat /etc/os-release
        echo "Detected configuration:"
        echo "OS: $OS_NAME"
        echo "Version: $OS_VERSION"
        echo "Architecture: $ARCH"
        echo "Repository URL: $REPO_URL"
    } >> "$LOG_FILE"
    
    echo "REPO_URL=$REPO_URL"
    echo "OS_VERSION=$OS_VERSION"
    echo "ARCH=$ARCH"
    echo "OS_NAME=$OS_NAME"
    return 0
}

# Configure Docker repository with enhanced error handling
configure_docker_repository() {
    log_info "$(get_message "docker.info.configuring")"
    
    # Clean up any existing Docker installations first
    log_info "Cleaning up existing Docker installations..."
    if ! output=$(sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io 2>&1); then
        log_warn "Failed to remove existing Docker packages: $output"
    fi
    
    if ! output=$(sudo apt-get purge -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io 2>&1); then
        log_warn "Failed to purge Docker packages: $output"
    fi
    
    sudo rm -rf /var/lib/docker /etc/docker /var/run/docker.sock /var/run/docker.pid
    sudo rm -rf /var/lib/containerd /etc/containerd /var/run/containerd
    sudo rm -f /etc/apt/sources.list.d/docker*.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    
    # Get repository information
    local repo_info
    if ! repo_info=$(configure_repository_url); then
        handle_error "Failed to configure repository URL" "Repository URL configuration failed" true
    fi
    
    # Parse repository info
    eval "$repo_info"
    
    # Install prerequisites for HTTPS repository
    log_info "Installing prerequisites..."
    if ! output=$(DEBIAN_FRONTEND=noninteractive sudo apt-get install -y ca-certificates curl gnupg lsb-release 2>&1); then
        handle_error "Failed to install prerequisites" "$output" true
    fi

    # Create keyrings directory
    sudo mkdir -p /etc/apt/keyrings

    # Download and add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    if ! output=$(curl -fsSL "$REPO_URL/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>&1); then
        handle_error "Failed to download and install Docker GPG key" "$output" true
    fi

    # Set up repository with proper formatting
    log_info "Adding Docker repository..."
    # Remove any existing Docker repository files
    sudo rm -f /etc/apt/sources.list.d/docker*.list
    
    # Add repository with exact formatting (no extra spaces)
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] $REPO_URL $OS_VERSION stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Print the exact repository line for debugging
    echo "Added repository line:"
    cat /etc/apt/sources.list.d/docker.list

    # Debug repository configuration
    log_info "Repository configuration:"
    {
        echo "Docker repository file content:"
        cat /etc/apt/sources.list.d/docker.list
        echo "All configured repositories:"
        ls -l /etc/apt/sources.list.d/
        echo "APT sources configuration:"
        cat /etc/apt/sources.list
        echo "Testing repository access:"
        curl -fsSL "$REPO_URL/dists/$OS_VERSION/stable/binary-$ARCH/Packages.gz" > /dev/null || echo "Failed to access repository packages"
    } >> "$LOG_FILE"
    
    # Test repository URL accessibility
    if ! curl -fsSL "$REPO_URL/dists/$OS_VERSION/stable/binary-$ARCH/Packages.gz" > /dev/null; then
        handle_error "Repository URL not accessible" "Failed to access: $REPO_URL/dists/$OS_VERSION/stable/binary-$ARCH/Packages.gz" true
    fi
    
    # Verify repository file content
    if ! grep -q "^deb.*$REPO_URL.*$OS_VERSION.*stable" /etc/apt/sources.list.d/docker.list; then
        handle_error "Repository file verification failed" "Repository file content is invalid" true
    fi

    # Additional repository setup for certain distributions
    case $OS_NAME in
        debian|raspbian)
            # Enable contrib and non-free repositories
            if ! output=$(sudo sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list 2>&1); then
                handle_error "Failed to enable additional repositories" "$output" true
            fi
            # Ensure security updates are enabled
            if ! grep -q "security" /etc/apt/sources.list; then
                echo "deb http://security.debian.org/debian-security $OS_VERSION-security main contrib non-free" | sudo tee -a /etc/apt/sources.list > /dev/null
            fi
            # Ensure updates repository is enabled
            if ! grep -q "$OS_VERSION-updates" /etc/apt/sources.list; then
                echo "deb http://deb.debian.org/debian $OS_VERSION-updates main contrib non-free" | sudo tee -a /etc/apt/sources.list > /dev/null
            fi
            ;;
        ubuntu)
            # Enable additional repositories
            for repo in universe multiverse restricted; do
                if ! output=$(sudo add-apt-repository -y "$repo" 2>&1); then
                    log_warn "Failed to enable $repo repository: $output"
                fi
            done
            # Ensure security updates are enabled
            if ! grep -q "security" /etc/apt/sources.list; then
                echo "deb http://security.ubuntu.com/ubuntu $OS_VERSION-security main restricted universe multiverse" | sudo tee -a /etc/apt/sources.list > /dev/null
            fi
            ;;
    esac

    # Update package lists after adding repositories
    log_info "Updating package lists after repository changes..."
    if ! output=$(DEBIAN_FRONTEND=noninteractive sudo apt-get update 2>&1); then
        handle_error "Failed to update package lists after repository changes" "$output" true
    fi

    # Fix permissions
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Update package lists with retries
    log_info "Updating package lists..."
    local retry_count=0
    local max_retries=3
    local success=false
    
    while [ $retry_count -lt $max_retries ]; do
        if output=$(DEBIAN_FRONTEND=noninteractive sudo apt-get update 2>&1); then
            success=true
            break
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warn "Failed to update package lists, retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    if [ "$success" = false ]; then
        handle_error "Failed to update package lists after $max_retries attempts" "$output" true
    fi
    
    # Verify Docker repository is accessible
    if ! apt-cache policy docker-ce >/dev/null 2>&1; then
        handle_error "Docker repository is not accessible" "Repository might not be properly configured for $OS_NAME $OS_VERSION" true
    fi
    
    log_info "Docker repository configured successfully"
    return 0
}

# Install Docker packages with enhanced error handling
install_docker_packages() {
    log_info "$(get_message "docker.info.installing")"
    
    # Get required packages from config
    local packages=$(yq eval '.docker.packages[].name' "$CONFIG_FILE")
    
    # Verify package list is not empty
    if [ -z "$packages" ]; then
        handle_error "No packages specified in config" "Package list is empty" true
    fi
    
    # First verify all packages are available
    while IFS= read -r pkg; do
        log_info "Checking availability of package: $pkg"
        
        # Check if package exists in repository
        if ! apt-cache show "$pkg" >/dev/null 2>&1; then
            # Get repository status for better error reporting
            local repo_status
            repo_status=$(cat /etc/apt/sources.list.d/docker.list 2>/dev/null || echo "Docker repository file not found")
            local error_details="Package: $pkg\nRepository status:\n$repo_status\nRepository URL: $REPO_URL\nOS: $OS_NAME $OS_VERSION\nArch: $ARCH"
            handle_error "Package not available in repository: $pkg" "$error_details" true
        fi
    done < <(echo "$packages")
    
    # Install each package with retry and enhanced error handling
    while IFS= read -r pkg; do
        local retry_count=0
        local max_retries=3
        local output
        local success=false
        
        while [ $retry_count -lt $max_retries ]; do
            log_info "$(get_message "docker.info.installing_prerequisite" "$pkg")"
            
            # First check if package is available
            if ! output=$(apt-cache policy "$pkg" 2>&1); then
                local error_details="Package not found in repositories\n"
                error_details+="Package: $pkg\n"
                error_details+="Repository status:\n$(cat /etc/apt/sources.list.d/docker.list)\n"
                error_details+="APT cache output:\n$output"
                handle_error "Package not available: $pkg" "$error_details" true
                return 1
            fi
            
            # Try to install the package
            if ! output=$(DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$pkg" 2>&1); then
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log_warn "Retry attempt $retry_count of $max_retries"
                    sleep 5
                    continue
                fi
                
                # If we've exhausted all retries, show detailed error
                local error_details="Package installation failed\n"
                error_details+="Package: $pkg\n"
                error_details+="Attempt: $retry_count of $max_retries\n"
                error_details+="Repository status:\n$(cat /etc/apt/sources.list.d/docker.list)\n"
                error_details+="Package status:\n$(apt-cache policy "$pkg")\n"
                error_details+="Installation output:\n$output"
                
                echo -e "\n${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║                  PACKAGE INSTALLATION ERROR                    ║${NC}"
                echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
                echo -e "${RED}║ Package: $pkg${NC}"
                echo -e "${RED}║ Status: Failed after $retry_count attempts${NC}"
                echo -e "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}"
                echo -e "${RED}║ Error Details:${NC}"
                echo -e "${RED}║ $output${NC}"
                echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
                
                handle_error "Failed to install package: $pkg" "$error_details" true
                return 1
            else
                success=true
                break
            fi
        done
        
        # Verify package installation
        if ! dpkg -l "$pkg" | grep -q "^ii"; then
            handle_error "Package verification failed: $pkg" "Package not properly installed" true
        fi
        
    done < <(echo "$packages")
    
    log_info "$(get_message "docker.info.installed")"
    return 0
}

# Setup Docker environment
setup_docker_environment() {
    log_info "$(get_message "docker.info.setup_start")"
    
    # Get system requirements
    local required_memory=$(yq eval '.docker.requirements.memory' "$CONFIG_FILE")
    local required_disk=$(yq eval '.docker.requirements.disk_space' "$CONFIG_FILE")
    local required_modules=$(yq eval '.docker.requirements.kernel_modules[]' "$CONFIG_FILE")
    
    # Check system resources
    local available_memory=$(free -m | awk '/Mem:/ {print $2}')
    local available_disk=$(df -m /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        handle_error "$(get_message "docker.info.system.memory_warning" "$available_memory" "$required_memory")" "Insufficient memory" true
    fi
    
    if [ "$available_disk" -lt "$required_disk" ]; then
        handle_error "$(get_message "docker.info.system.disk_warning" "$available_disk" "$required_disk")" "Insufficient disk space" true
    fi
    
    # Load required kernel modules
    local output
    while IFS= read -r module; do
        if ! lsmod | grep -q "^$module "; then
            log_info "$(get_message "docker.info.system.module_loading" "$module")"
            if ! output=$(sudo modprobe "$module" 2>&1); then
                handle_error "Failed to load kernel module $module" "$output" true
            fi
            echo "$module" | sudo tee -a /etc/modules-load.d/docker.conf > /dev/null
        fi
    done < <(echo "$required_modules")
    
    # Configure network
    local network_name=$(yq eval '.docker.network.name' "$CONFIG_FILE")
    local network_driver=$(yq eval '.docker.network.driver' "$CONFIG_FILE")
    local network_subnet=$(yq eval '.docker.network.subnet' "$CONFIG_FILE")
    
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        if ! output=$(docker network create --driver "$network_driver" --subnet "$network_subnet" "$network_name" 2>&1); then
            handle_error "$(get_message "docker.error.network_create")" "$output" true
        fi
    fi
    
    log_info "$(get_message "docker.info.configured")"
    return 0
}

# Test Docker setup
test_component() {
    log_info "$(get_message "docker.info.testing")"
    
    local output
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        output=$(systemctl status docker 2>&1)
        handle_error "$(get_message "docker.error.docker_not_installed")" "$output" true
    fi
    
    # Check Docker version
    if ! docker --version >/dev/null 2>&1; then
        handle_error "$(get_message "docker.error.docker_not_installed")" "Docker command not found" true
    fi
    
    # Check Docker network
    local network_name=$(yq eval '.docker.network.name' "$CONFIG_FILE")
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        handle_error "$(get_message "docker.error.network_not_found")" "Network $network_name does not exist" true
    fi
    
    # Test Docker functionality
    if ! output=$(docker run --rm hello-world 2>&1); then
        handle_error "$(get_message "docker.error.test_failed")" "$output" true
    fi
    
    log_info "$(get_message "docker.info.tests_passed")"
    return 0
}

# Check prerequisites
check_prerequisites() {
    log_info "$(get_message "docker.info.prerequisites.checking")"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        handle_error "$(get_message "docker.error.root_required")" "Script must be run as root" true
    fi
    
    # Check system setup
    if [ ! -f "/opt/control-panel/.system_setup_complete" ]; then
        handle_error "$(get_message "docker.error.system_setup")" "System setup not completed" true
    fi
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed, will be reconfigured"
    fi
    
    log_info "$(get_message "docker.info.prerequisites.passed")"
    return 0
}

# Backup function
backup_component() {
    log_info "$(get_message "docker.info.backup.start")"
    
    # Get backup directory from config
    local backup_dir=$(yq eval '.deployment.backup_dir' "$CONFIG_FILE")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${backup_dir}/${timestamp}"
    mkdir -p "$backup_path"
    
    local output
    # Backup Docker configuration
    if [ -d "/etc/docker" ]; then
        if ! output=$(cp -r "/etc/docker" "${backup_path}/" 2>&1); then
            handle_error "Failed to backup Docker configuration" "$output" true
        fi
    fi
    
    # Backup Docker service file
    if [ -f "/lib/systemd/system/docker.service" ]; then
        if ! output=$(cp "/lib/systemd/system/docker.service" "${backup_path}/" 2>&1); then
            handle_error "Failed to backup Docker service file" "$output" true
        fi
    fi
    
    # Create backup metadata
    cat > "${backup_path}/metadata.yaml" << EOF
version: ${COMPONENT_VERSION}
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
component: ${COMPONENT_NAME}
config_file: ${CONFIG_FILE}
docker_version: $(docker --version 2>/dev/null || echo "not_installed")
EOF
    
    log_info "$(get_message "docker.info.backup.complete" "${backup_path}")"
    return 0
}

# Rollback function
rollback_component() {
    log_info "$(get_message "docker.info.rollback.start")"
    
    # Find latest backup
    local backup_dir=$(yq eval '.deployment.backup_dir' "$CONFIG_FILE")
    local latest_backup=$(ls -td ${backup_dir}/*/ 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        handle_error "$(get_message "docker.error.no_backup")" "No backup found in $backup_dir" true
    fi
    
    local output
    # Stop Docker service
    if ! output=$(sudo systemctl stop docker 2>&1); then
        handle_error "Failed to stop Docker service" "$output" true
    fi
    
    # Restore Docker configuration
    if [ -d "${latest_backup}/docker" ]; then
        if ! output=$(sudo cp -r "${latest_backup}/docker" "/etc/" 2>&1); then
            handle_error "Failed to restore Docker configuration" "$output" true
        fi
    fi
    
    # Restore Docker service file
    if [ -f "${latest_backup}/docker.service" ]; then
        if ! output=$(sudo cp "${latest_backup}/docker.service" "/lib/systemd/system/" 2>&1); then
            handle_error "Failed to restore Docker service file" "$output" true
        fi
    fi
    
    # Reload systemd and restart Docker
    if ! output=$(sudo systemctl daemon-reload 2>&1); then
        handle_error "Failed to reload systemd" "$output" true
    fi
    
    if ! output=$(sudo systemctl start docker 2>&1); then
        handle_error "Failed to start Docker service" "$output" true
    fi
    
    log_info "$(get_message "docker.info.rollback.complete")"
    return 0
}

# Main setup function
setup_component() {
    log_info "$(get_message "docker.info.setup_start")"
    
    # Load paths from config
    load_paths
    
    # Check version compatibility
    log_info "Checking version compatibility..."
    if ! check_version "$COMPONENT_VERSION" "$REQUIRED_VERSION"; then
        handle_error "Version compatibility check failed" "Required version: $REQUIRED_VERSION, Current version: $COMPONENT_VERSION" true
    fi
    
    # Check deployment status and create backup if needed
    log_info "Checking deployment status..."
    if check_deployment_status; then
        log_warn "Previous deployment found. Creating backup before proceeding..."
        if ! backup_component; then
            handle_error "$(get_message "docker.error.backup_failed")" "Failed to create backup" true
        fi
    fi
    
    # Check prerequisites
    if ! check_prerequisites; then
        handle_error "Prerequisites check failed" "One or more prerequisites not met" true
    fi
    
    # Configure Docker repository
    if ! configure_docker_repository; then
        handle_error "Failed to configure Docker repository" "Repository configuration failed" true
    fi
    
    # Install Docker packages
    if ! install_docker_packages; then
        handle_error "Failed to install Docker packages" "Package installation failed" true
    fi
    
    # Verify installation
    log_info "Verifying package installation..."
    if ! dpkg -l | grep -q docker-ce; then
        handle_error "Docker CE package not found after installation" "Package verification failed" true
    fi
    
    # Setup Docker environment
    if ! setup_docker_environment; then
        handle_error "Failed to setup Docker environment" "Environment setup failed" true
    fi
    
    # Create setup completion marker
    echo "$COMPONENT_VERSION" > "$STATUS_FILE"
    if [ $? -ne 0 ]; then
        handle_error "$(get_message "docker.error.marker_create")" "Failed to write to $STATUS_FILE" true
    fi
    
    # Test the setup
    if ! test_component; then
        handle_error "$(get_message "docker.error.setup_verify")" "Component tests failed" true
        rollback_component
    fi
    
    log_info "$(get_message "docker.info.setup_complete")"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set up error handling
    setup_error_handling
    
    # Run setup
    if ! setup_component; then
        log_error "Failed to deploy docker component"
        exit 1
    fi
fi
