#!/bin/bash
if [ -z "$BASH_VERSION" ]; then
  echo "This script requires Bash. Re-running with Bash..."
  exec bash "$0" "$@"
fi

# Exit on error
set -e

# Define colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

# Trap errors: if an error occurs, display a message explaining the issue
trap 'echo -e "${RED}[ERROR] An error occurred during script execution. Check the messages above for details on missing installations or issues.";' ERR

# Logging functions for clearer output
log_info() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Check Hailo-8 tools
log_info "Checking Hailo-8 tools..."
if ! command -v hailortcli >/dev/null 2>&1; then
    log_error "Hailo-8 tools not found. Please ensure that Hailo-8 drivers and runtime are installed."
    exit 1
fi
log_success "Hailo-8 tools found."

# 2. Verify Hailo-8 device
log_info "Verifying Hailo-8 device..."
if ! hailortcli fw-control identify >/dev/null 2>&1; then
    log_error "Hailo-8 device not detected or not accessible. Check the connection and permissions."
    log_info "Try running: sudo usermod -aG hailo \$USER"
    exit 1
fi
log_success "Hailo-8 device verified."

# 3. Update system packages
log_info "Updating system packages..."
sudo apt update && sudo apt upgrade -y
log_success "System packages updated."

# 4. Install system dependencies
log_info "Installing system dependencies..."
sudo apt install -y \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    nginx 
log_success "System dependencies installed."

# 5. Create Python virtual environment
log_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
log_success "Python virtual environment created and activated."

# 6. Install Python dependencies
log_info "Installing Python dependencies..."
pip install -r requirements.txt
log_success "Python dependencies installed."

# 7. Install Hailo Python API
log_info "Installing Hailo Python API..."
pip install hailo-ai
log_success "Hailo Python API installed."

# 8. Build frontend
log_info "Building frontend..."
cd frontend
npm install
npm run build
cd ..
log_success "Frontend built."

# 9. Configure nginx
log_info "Configuring nginx..."
sudo cp deployment/nginx.conf /etc/nginx/sites-available/jadeai
sudo ln -sf /etc/nginx/sites-available/jadeai /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx
log_success "nginx configured."

# 10. Install systemd service
log_info "Installing systemd service..."
sudo cp deployment/jadeai.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable jadeai
sudo systemctl start jadeai
log_success "Systemd service installed and started."

# 11. Set up Bluetooth HID
log_info "Setting up Bluetooth HID device..."
chmod +x deployment/bluetooth_hid_setup.sh
sudo ./deployment/bluetooth_hid_setup.sh
log_success "Bluetooth HID device configured."

# Final success message
echo -e "${GREEN}Installation complete!${NC}"
echo "JadeAI is now running at http://localhost"
echo "Bluetooth HID device is available as 'JadeAI HID'"
