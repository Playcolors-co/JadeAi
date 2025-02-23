#!/bin/bash

# Exit on error
set -e

echo "Installing JadeAI for Raspberry Pi 5 with Hailo-8..."

# Check Hailo-8 tools
echo "Checking Hailo-8 tools..."
if ! command -v hailortcli >/dev/null 2>&1; then
    echo "Error: Hailo-8 tools not found. Please ensure Hailo-8 drivers and runtime are installed."
    exit 1
fi

# Verify Hailo-8 device
echo "Verifying Hailo-8 device..."
if ! hailortcli fw-control identify >/dev/null 2>&1; then
    echo "Error: Hailo-8 device not detected or not accessible. Please check the connection and permissions."
    echo "Try running: sudo usermod -aG hailo $USER"
    exit 1
fi

# Update system
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install system dependencies
echo "Installing system dependencies..."
sudo apt install -y \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    nginx 

# Create virtual environment
echo "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
echo "Installing Python dependencies..."
pip install -r requirements.txt

# Install Hailo Python API
echo "Installing Hailo Python API..."
pip install hailo-ai

# Build frontend
echo "Building frontend..."
cd frontend
npm install
npm run build
cd ..

# Configure nginx
echo "Configuring nginx..."
sudo cp deployment/nginx.conf /etc/nginx/sites-available/jadeai
sudo ln -sf /etc/nginx/sites-available/jadeai /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

# Install systemd service
echo "Installing systemd service..."
sudo cp deployment/jadeai.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable jadeai
sudo systemctl start jadeai

# Setup Bluetooth HID
echo "Setting up Bluetooth HID device..."
chmod +x deployment/bluetooth_hid_setup.sh
sudo ./deployment/bluetooth_hid_setup.sh

echo "Installation complete!"
echo "JadeAI is now running at http://localhost"
echo "Bluetooth HID device is available as 'JadeAI HID'"
