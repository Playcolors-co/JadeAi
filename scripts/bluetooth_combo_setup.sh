#!/bin/bash

# Source common functions
source "$(dirname "$0")/common.sh"

# HID component version and configuration
COMPONENT_VERSION="1.1.0"
HID_CONFIG="/opt/control-panel/config/hid.json"
BLUETOOTH_SERVICE="bluetooth"
HID_SERVICE="hid-service"
HID_SYSTEMD_SERVICE="/etc/systemd/system/hid-service.service"
HID_SCRIPT="/opt/control-panel/scripts/hid_emulator.py"

# Test HID setup
test_hid() {
    log_info "Testing HID setup..."
    
    # Check Bluetooth service
    if ! check_service "$BLUETOOTH_SERVICE"; then
        log_error "Bluetooth service is not running"
        return 1
    fi
    
    # Check HID service
    if ! check_service "$HID_SERVICE"; then
        log_error "HID service is not running"
        return 1
    fi
    
    # Check if HID device exists
    if ! ls /dev/input/event* 2>/dev/null | grep -q .; then
        log_error "No HID devices found"
        return 1
    fi
    
    # Check if configuration exists
    if [ ! -f "$HID_CONFIG" ]; then
        log_error "HID configuration file not found"
        return 1
    fi
    
    # Check if HID script exists
    if [ ! -f "$HID_SCRIPT" ]; then
        log_error "HID emulator script not found"
        return 1
    fi
    
    log_info "HID tests passed successfully"
    return 0
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking HID prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
    
    # Check system setup
    if [ ! -f "/opt/control-panel/.system_setup_complete" ]; then
        log_error "System setup must be completed first"
        return 1
    fi
    
    # Check required packages
    local required_packages=(
        bluetooth
        bluez
        bluez-tools
        python3-dbus
        python3-evdev
        python3-pip
        python3-setuptools
    )
    
    for pkg in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_info "Installing prerequisite: $pkg"
            if ! apt-get install -y "$pkg"; then
                log_error "Failed to install prerequisite: $pkg"
                return 1
            fi
        fi
    done
    
    # Install Python packages
    log_info "Installing Python packages..."
    if ! pip3 install evdev dbus-python; then
        log_error "Failed to install Python packages"
        return 1
    fi
    
    log_info "Prerequisites check passed"
    return 0
}

# Configure Bluetooth
configure_bluetooth() {
    log_info "Configuring Bluetooth..."
    
    # Enable Bluetooth service
    systemctl enable bluetooth
    systemctl start bluetooth
    
    # Configure Bluetooth for HID
    cat > "/etc/bluetooth/main.conf" << EOF
[General]
Class = 0x000540
DiscoverableTimeout = 0
PairableTimeout = 0
Privacy = off

[Policy]
AutoEnable=true
EOF
    
    # Restart Bluetooth service
    if ! restart_service "bluetooth"; then
        return 1
    fi
    
    log_info "Bluetooth configured successfully"
    return 0
}

# Create HID emulator script
create_hid_script() {
    log_info "Creating HID emulator script..."
    
    # Create scripts directory
    mkdir -p "$(dirname "$HID_SCRIPT")"
    
    # Create Python script
    cat > "$HID_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import dbus
import evdev
from evdev import UInput, ecodes as e
import time
import json
import os

class HIDEmulator:
    def __init__(self):
        self.bus = dbus.SystemBus()
        self.bluetooth = self.bus.get_object('org.bluez', '/')
        self.adapter = self.find_adapter()
        
        # Create virtual HID device
        cap = {
            e.EV_KEY: [e.KEY_A, e.KEY_B],  # Example keys
            e.EV_REL: [e.REL_X, e.REL_Y],  # Mouse movement
            e.EV_MSC: [e.MSC_SCAN],
        }
        self.device = UInput(cap, name="Virtual HID Device")
    
    def find_adapter(self):
        remote_om = dbus.Interface(self.bluetooth, 'org.freedesktop.DBus.ObjectManager')
        objects = remote_om.GetManagedObjects()
        
        for o, props in objects.items():
            if 'org.bluez.Adapter1' in props:
                return o
        
        return None
    
    def setup_profile(self):
        profile_path = "/org/bluez/hid"
        profile = {
            "Name": "Virtual HID Device",
            "Role": "server",
            "RequireAuthentication": False,
            "RequireAuthorization": False,
            "ServiceRecord": """
                <?xml version="1.0" encoding="UTF-8" ?>
                <record>
                    <attribute id="0x0001">
                        <sequence>
                            <uuid value="0x1124"/>
                        </sequence>
                    </attribute>
                    <attribute id="0x0004">
                        <sequence>
                            <sequence>
                                <uuid value="0x0100"/>
                                <uint16 value="0x0011"/>
                            </sequence>
                            <sequence>
                                <uuid value="0x0011"/>
                            </sequence>
                        </sequence>
                    </attribute>
                    <attribute id="0x0005">
                        <sequence>
                            <uuid value="0x1124"/>
                        </sequence>
                    </attribute>
                    <attribute id="0x0006">
                        <sequence>
                            <uint16 value="0x656e"/>
                            <uint16 value="0x006a"/>
                            <uint16 value="0x0100"/>
                        </sequence>
                    </attribute>
                    <attribute id="0x0009">
                        <sequence>
                            <sequence>
                                <uuid value="0x1124"/>
                                <uint16 value="0x0100"/>
                            </sequence>
                        </sequence>
                    </attribute>
                    <attribute id="0x000d">
                        <sequence>
                            <sequence>
                                <sequence>
                                    <uuid value="0x0100"/>
                                    <uint16 value="0x0013"/>
                                </sequence>
                                <sequence>
                                    <uuid value="0x0011"/>
                                </sequence>
                            </sequence>
                        </sequence>
                    </attribute>
                </record>
            """
        }
        
        profile_manager = dbus.Interface(
            self.bus.get_object("org.bluez", "/org/bluez"),
            "org.bluez.ProfileManager1"
        )
        
        profile_manager.RegisterProfile(profile_path, "00001124-0000-1000-8000-00805f9b34fb", profile)
    
    def run(self):
        try:
            self.setup_profile()
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            self.device.close()

if __name__ == '__main__':
    emulator = HIDEmulator()
    emulator.run()
EOF
    
    # Make script executable
    chmod +x "$HID_SCRIPT"
    
    log_info "HID emulator script created successfully"
    return 0
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    # Create service file
    cat > "$HID_SYSTEMD_SERVICE" << EOF
[Unit]
Description=HID Emulator Service
After=bluetooth.service
Requires=bluetooth.service

[Service]
ExecStart=/usr/bin/python3 $HID_SCRIPT
Restart=always
User=root
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable and start service
    systemctl enable hid-service
    if ! restart_service "hid-service"; then
        return 1
    fi
    
    log_info "Systemd service created successfully"
    return 0
}

# Configure HID
configure_hid() {
    log_info "Configuring HID..."
    
    # Create configuration
    cat > "$HID_CONFIG" << EOF
{
    "version": "$COMPONENT_VERSION",
    "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "service": "$HID_SERVICE",
    "script": "$HID_SCRIPT",
    "device": {
        "name": "Virtual HID Device",
        "type": "combo",
        "capabilities": [
            "keyboard",
            "mouse"
        ]
    },
    "bluetooth": {
        "enabled": true,
        "discoverable": true,
        "pairable": true
    }
}
EOF
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create HID configuration"
        return 1
    fi
    
    log_info "HID configured successfully"
    return 0
}

# Main setup function
setup_hid() {
    log_info "Starting HID setup..."
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Configure Bluetooth
    if ! configure_bluetooth; then
        return 1
    fi
    
    # Create HID script
    if ! create_hid_script; then
        return 1
    fi
    
    # Create systemd service
    if ! create_systemd_service; then
        return 1
    fi
    
    # Configure HID
    if ! configure_hid; then
        return 1
    fi
    
    # Create setup completion marker
    touch "/opt/control-panel/.bluetooth_combo_setup_complete"
    if [ $? -ne 0 ]; then
        log_error "Failed to create setup completion marker"
        return 1
    fi
    
    # Test the setup
    if ! test_hid; then
        log_error "HID setup verification failed"
        return 1
    fi
    
    log_info "HID setup completed successfully"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    
    # Set up error handling
    setup_error_handling
    
    # Run setup
    if ! setup_hid; then
        exit 1
    fi
fi
