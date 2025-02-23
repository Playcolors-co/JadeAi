# JadeAI 0.1.0.0 - Raspberry Pi 5 with Hailo-8 Deployment

## Prerequisites

1. Raspberry Pi 5 with Raspberry Pi OS (64-bit)
2. Hailo-8 AI Accelerator
3. Internet connection for package installation

## Installation

1. Install Hailo-8 drivers and runtime:
   ```bash
   # Add Hailo repository
   echo "deb https://hailo-hailort.s3.eu-west-2.amazonaws.com/HailoRT/2.10.0/raspbian/arm64 ./" | sudo tee /etc/apt/sources.list.d/hailo.list
   curl https://hailo-hailort.s3.eu-west-2.amazonaws.com/HailoRT/2.10.0/raspbian/arm64/hailo.gpg | sudo apt-key add -
   
   # Install Hailo packages
   sudo apt update
   sudo apt install -y libhailort hailort-driver-dkms libhailort-dev
   ```

2. Run the installation script:
   ```bash
   sudo ./install.sh
   ```

3. The web interface will be available at http://localhost

## Configuration

1. The web admin interface is accessible at http://localhost
2. Default login credentials:
   - Username: admin
   - Password: jadeai

## Hailo-8 Setup

1. Verify Hailo-8 detection:
   ```bash
   sudo hailortcli fw-control identify
   ```

2. Run Hailo setup script:
   ```bash
   python3 deployment/hailo_setup.py
   ```

## Troubleshooting

1. Check service status:
   ```bash
   sudo systemctl status jadeai
   ```

2. View logs:
   ```bash
   sudo journalctl -u jadeai -f
   ```

3. Check Hailo-8 status:
   ```bash
   sudo hailortcli device-info
   ```
