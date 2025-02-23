#!/bin/bash

# Exit on error
set -e

echo "Setting up Bluetooth HID Device (Keyboard + Mouse)..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Install required packages
echo "Installing required packages..."
apt-get update
apt-get install -y bluetooth bluez bluez-tools python3-dbus python3-gi

# Enable Bluetooth service
echo "Enabling Bluetooth service..."
systemctl enable bluetooth
systemctl start bluetooth

# Configure Bluetooth for HID
echo "Configuring Bluetooth HID..."
cat > /etc/bluetooth/main.conf << EOL
[General]
Name = JadeAI HID
Class = 0x002540
DiscoverableTimeout = 0
PairableTimeout = 0
Privacy = device

[Policy]
AutoEnable = true

[LE]
MinConnectionInterval = 7
MaxConnectionInterval = 9
ConnectionLatency = 0
EOL

# Create HID profile
echo "Creating HID profile..."
cat > /etc/dbus-1/system.d/org.bluez.input.conf << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="org.bluez"/>
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.Agent1"/>
    <allow send_interface="org.bluez.Profile1"/>
    <allow send_interface="org.bluez.GattCharacteristic1"/>
    <allow send_interface="org.bluez.GattDescriptor1"/>
  </policy>
</busconfig>
EOL

# Create systemd service for HID
echo "Creating systemd service..."
cat > /etc/systemd/system/jadeai-hid.service << EOL
[Unit]
Description=JadeAI Bluetooth HID Service
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/jadeai/bluetooth_hid.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOL

# Create Python script for HID functionality
echo "Creating HID control script..."
mkdir -p /opt/jadeai
cat > /opt/jadeai/bluetooth_hid.py << 'EOL'
#!/usr/bin/env python3
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
import time
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('JadeAI-HID')

class BluetoothHID(dbus.service.Object):
    def __init__(self):
        bus = dbus.SystemBus()
        dbus.service.Object.__init__(self, bus, "/org/bluez/jadeai_hid")
        
        self.bus = bus
        self.mainloop = GLib.MainLoop()
        
        # HID descriptor for keyboard + mouse combo
        self.descriptor = bytes([
            0x05, 0x01,  # Usage Page (Generic Desktop)
            0x09, 0x06,  # Usage (Keyboard)
            0xA1, 0x01,  # Collection (Application)
            0x85, 0x01,  # Report ID (1)
            0x05, 0x07,  # Usage Page (Key Codes)
            0x19, 0x00,  # Usage Minimum (0)
            0x29, 0xFF,  # Usage Maximum (255)
            0x15, 0x00,  # Logical Minimum (0)
            0x25, 0xFF,  # Logical Maximum (255)
            0x75, 0x08,  # Report Size (8)
            0x95, 0x06,  # Report Count (6)
            0x81, 0x00,  # Input (Data, Array)
            0xC0,        # End Collection
            
            0x05, 0x01,  # Usage Page (Generic Desktop)
            0x09, 0x02,  # Usage (Mouse)
            0xA1, 0x01,  # Collection (Application)
            0x85, 0x02,  # Report ID (2)
            0x09, 0x01,  # Usage (Pointer)
            0xA1, 0x00,  # Collection (Physical)
            0x05, 0x09,  # Usage Page (Button)
            0x19, 0x01,  # Usage Minimum (Button 1)
            0x29, 0x03,  # Usage Maximum (Button 3)
            0x15, 0x00,  # Logical Minimum (0)
            0x25, 0x01,  # Logical Maximum (1)
            0x95, 0x03,  # Report Count (3)
            0x75, 0x01,  # Report Size (1)
            0x81, 0x02,  # Input (Data, Variable, Absolute)
            0x95, 0x01,  # Report Count (1)
            0x75, 0x05,  # Report Size (5)
            0x81, 0x03,  # Input (Constant)
            0x05, 0x01,  # Usage Page (Generic Desktop)
            0x09, 0x30,  # Usage (X)
            0x09, 0x31,  # Usage (Y)
            0x09, 0x38,  # Usage (Wheel)
            0x15, 0x81,  # Logical Minimum (-127)
            0x25, 0x7F,  # Logical Maximum (127)
            0x75, 0x08,  # Report Size (8)
            0x95, 0x03,  # Report Count (3)
            0x81, 0x06,  # Input (Data, Variable, Relative)
            0xC0,        # End Collection
            0xC0         # End Collection
        ])

        # Create SDP record XML
        self.sdp_record = self.create_sdp_record()

    def create_sdp_record(self):
        record = ET.Element('record')
        
        # Service Class ID List
        attr = ET.SubElement(record, 'attribute')
        attr.set('id', '0x0001')
        seq = ET.SubElement(attr, 'sequence')
        uuid = ET.SubElement(seq, 'uuid')
        uuid.set('value', '0x1124')  # HID Service Class

        # Protocol Descriptor List
        attr = ET.SubElement(record, 'attribute')
        attr.set('id', '0x0004')
        seq = ET.SubElement(attr, 'sequence')
        seq_l2cap = ET.SubElement(seq, 'sequence')
        uuid_l2cap = ET.SubElement(seq_l2cap, 'uuid')
        uuid_l2cap.set('value', '0x0100')  # L2CAP
        seq_hidp = ET.SubElement(seq, 'sequence')
        uuid_hidp = ET.SubElement(seq_hidp, 'uuid')
        uuid_hidp.set('value', '0x0011')  # HIDP

        # Language Base Attribute ID List
        attr = ET.SubElement(record, 'attribute')
        attr.set('id', '0x0006')
        seq = ET.SubElement(attr, 'sequence')
        uint = ET.SubElement(seq, 'uint16')
        uint.set('value', '0x656e')  # English
        uint = ET.SubElement(seq, 'uint16')
        uint.set('value', '0x006a')  # UTF-8
        uint = ET.SubElement(seq, 'uint16')
        uint.set('value', '0x0100')  # Primary Language Base

        # HID Descriptor List
        attr = ET.SubElement(record, 'attribute')
        attr.set('id', '0x0206')
        seq = ET.SubElement(attr, 'sequence')
        seq_desc = ET.SubElement(seq, 'sequence')
        uint = ET.SubElement(seq_desc, 'uint8')
        uint.set('value', '0x22')  # Report Descriptor
        text = ET.SubElement(seq_desc, 'text')
        text.text = self.descriptor.hex()

        # HID Additional Protocol Descriptor Lists
        attr = ET.SubElement(record, 'attribute')
        attr.set('id', '0x0200')
        seq = ET.SubElement(attr, 'sequence')
        seq_proto = ET.SubElement(seq, 'sequence')
        uint = ET.SubElement(seq_proto, 'uint16')
        uint.set('value', '0x0100')  # L2CAP
        uint = ET.SubElement(seq_proto, 'uint16')
        uint.set('value', '0x0011')  # HIDP

        return ET.tostring(record, encoding='unicode')

    @dbus.service.method("org.bluez.Profile1",
                        in_signature="", out_signature="")
    def Release(self):
        logger.info("Release")
        self.mainloop.quit()

    @dbus.service.method("org.bluez.Profile1",
                        in_signature="oha{sv}", out_signature="")
    def NewConnection(self, device, fd, properties):
        logger.info(f"New Connection: {device}")
        self.device_path = device
        self.fd = fd

    @dbus.service.method("org.bluez.Profile1",
                        in_signature="o", out_signature="")
    def RequestDisconnection(self, device):
        logger.info(f"Request Disconnection: {device}")
        if hasattr(self, 'fd'):
            del self.fd
        if hasattr(self, 'device_path'):
            del self.device_path

    def register_hid_device(self):
        manager = dbus.Interface(
            self.bus.get_object("org.bluez", "/org/bluez"),
            "org.bluez.ProfileManager1"
        )
        
        profile = {
            "Name": "JadeAI HID Device",
            "Role": "server",
            "ServiceRecord": self.sdp_record,
            "RequireAuthentication": False,
            "RequireAuthorization": False,
            "AutoConnect": True,
            "ServiceUUID": "00001124-0000-1000-8000-00805f9b34fb"
        }
        
        try:
            manager.RegisterProfile("/org/bluez/jadeai_hid", 
                                 "00001124-0000-1000-8000-00805f9b34fb",
                                 profile)
            logger.info("HID Profile registered successfully")
        except Exception as e:
            logger.error(f"Failed to register HID profile: {e}")
            raise

    def run(self):
        try:
            self.register_hid_device()
            logger.info("HID Device registered and running...")
            self.mainloop.run()
        except Exception as e:
            logger.error(f"Error running HID service: {e}")
            raise

if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    hid = BluetoothHID()
    hid.run()
EOL

# Make scripts executable
chmod +x /opt/jadeai/bluetooth_hid.py

# Reload systemd and start service
echo "Starting HID service..."
systemctl daemon-reload
systemctl enable jadeai-hid
systemctl start jadeai-hid

echo "Bluetooth HID setup complete!"
echo "Device will appear as 'JadeAI HID' in Bluetooth settings"
echo "Use 'bluetoothctl' to manage connections"
echo "Check logs with: journalctl -u jadeai-hid -f"
