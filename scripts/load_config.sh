#!/bin/bash

# Version declaration
JADE_CONFIG_VERSION="1.0.0"
REQUIRED_COMMON_VERSION="1.0.0"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Check common.sh version
if ! check_version "$JADE_COMMON_VERSION" "$REQUIRED_COMMON_VERSION"; then
    log_error "config.version_mismatch" "$REQUIRED_COMMON_VERSION" "$JADE_COMMON_VERSION"
    exit 1
fi

# Initialize logging
init_logging "config"

# Function to get the project root directory
get_project_root() {
    local current_dir="$1"
    while [[ ! -d "$current_dir/config" && "$current_dir" != "/" ]]; do
        current_dir="$(dirname "$current_dir")"
    done
    if [[ -d "$current_dir/config" ]]; then
        echo "$current_dir"
    else
        log_error "config.root_not_found"
        return 1
    fi
}

# Function to install required tools
install_tools() {
    log_info "config.tools.checking"
    
    # Install jq if not present
    if ! command -v jq >/dev/null 2>&1; then
        log_info "config.tools.installing" "jq"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if ! brew install jq; then
                log_error "config.tools.install_failed" "jq"
                return 1
            fi
        else
            if ! sudo apt-get update && sudo apt-get install -y jq; then
                log_error "config.tools.install_failed" "jq"
                return 1
            fi
        fi
    fi
    
    # Install yq if not present
    if ! command -v yq >/dev/null 2>&1; then
        log_info "config.tools.installing" "yq"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if ! brew install yq; then
                log_error "config.tools.install_failed" "yq"
                return 1
            fi
        else
            ARCH=$(uname -m)
            YQ_VERSION="v4.40.5"
            if [ "$ARCH" = "x86_64" ]; then
                sudo wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O /usr/bin/yq
            elif [ "$ARCH" = "aarch64" ]; then
                sudo wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm64 -O /usr/bin/yq
            else
                log_error "config.tools.unsupported_arch" "$ARCH"
                return 1
            fi
            sudo chmod +x /usr/bin/yq
        fi
    fi
    
    log_info "config.tools.success"
    return 0
}

# Function to load JSON configuration
load_json() {
    local file=$1
    if [ ! -f "$file" ]; then
        log_error "config.file_not_found" "$file"
        return 1
    fi
    
    # Validate JSON format
    if ! jq . "$file" >/dev/null 2>&1; then
        log_error "config.invalid_json" "$file"
        return 1
    fi
    
    cat "$file"
}

# Function to load YAML configuration
load_yaml() {
    local file=$1
    if [ ! -f "$file" ]; then
        log_error "config.file_not_found" "$file"
        return 1
    fi
    
    # Validate YAML format
    if ! yq eval . "$file" >/dev/null 2>&1; then
        log_error "config.invalid_yaml" "$file"
        return 1
    fi
    
    cat "$file"
}

# Function to get a value from JSON using jq
get_json_value() {
    local json=$1
    local key=$2
    local value
    
    value=$(echo "$json" | jq -r "$key")
    if [ "$value" = "null" ]; then
        log_error "config.key_not_found" "$key"
        return 1
    fi
    
    echo "$value"
}

# Function to get a value from YAML using yq
get_yaml_value() {
    local yaml=$1
    local key=$2
    local value
    
    value=$(echo "$yaml" | yq eval "$key" -)
    if [ "$value" = "null" ]; then
        log_error "config.key_not_found" "$key"
        return 1
    fi
    
    echo "$value"
}

# Function to format message with parameters
format_message() {
    local message=$1
    shift
    local i=0
    for param in "$@"; do
        message=${message//\{$i\}/$param}
        i=$((i + 1))
    done
    echo "$message"
}

# Function to load messages for a component
load_messages() {
    local component=$1
    local lang=${2:-en}
    local project_root
    project_root=$(get_project_root "$(dirname "${BASH_SOURCE[0]}")") || return 1
    local config_dir="$project_root/config"
    
    # Load component-specific messages if they exist
    if [ -n "$component" ] && [ "$component" != "deploy" ]; then
        local msg_file="$config_dir/messages_${component}_${lang}.json"
        if [ -f "$msg_file" ]; then
            load_json "$msg_file"
            return
        fi
    fi
    
    # Load general messages
    local msg_file="$config_dir/messages_${lang}.json"
    if [ -f "$msg_file" ]; then
        load_json "$msg_file"
        return
    fi
    
    log_error "config.messages_not_found" "$component" "$lang"
    return 1
}

# Function to load component configuration
load_component_config() {
    local component=$1
    local project_root
    project_root=$(get_project_root "$(dirname "${BASH_SOURCE[0]}")") || return 1
    local config_dir="$project_root/config"
    
    # Try YAML first
    local yaml_file="$config_dir/${component}.yaml"
    if [ -f "$yaml_file" ]; then
        load_yaml "$yaml_file"
        return
    fi
    
    # Try JSON as fallback
    local json_file="$config_dir/${component}.json"
    if [ -f "$json_file" ]; then
        load_json "$json_file"
        return
    fi
    
    log_error "config.component_not_found" "$component"
    return 1
}

# Function to get a message
get_message() {
    local messages=$1
    local component=$2
    local category=$3
    local key=$4
    shift 4
    
    # Get the message template
    local template
    template=$(get_json_value "$messages" ".$component.$category.$key") || return 1
    
    # Format the message with parameters
    format_message "$template" "$@"
}

# Function to get a configuration value
get_config() {
    local config=$1
    local key=$2
    local format=${3:-yaml}  # Default to YAML
    
    if [ "$format" = "yaml" ]; then
        get_yaml_value "$config" "$key"
    else
        get_json_value "$config" "$key"
    fi
}

# Set up error handling
setup_error_handling

# Install required tools
install_tools || exit 1
