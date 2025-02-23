#!/bin/bash

# Exit on error
set -e

echo "Installing JadeAI for Raspberry Pi 5 with Hailo-8..."

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
    nginx \
    libhailort \
    hailort-driver-dkms \
    libhailort-dev

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

echo "Installation complete!"
echo "JadeAI is now running at http://localhost"
