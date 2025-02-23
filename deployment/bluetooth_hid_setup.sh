#!/bin/bash

# Exit on error
set -e

CONFIG_BACKUP_DIR="/opt/jadeai/bluetooth_backup"
HID_SERVICE="/etc/systemd/system/jadeai-hid.service"
HID_SCRIPT="/opt/jadeai/bluetooth_hid.py"
SDP_FILE="/opt/jadeai/hid_sdp.xml"
BLUEZ_CONF="/etc/bluetooth/main.conf"

echo "==== Bluetooth Dual Mode Setup ===="
echo "This script configures Raspberry Pi as a Bluetooth HID device (Keyboard + Mouse)"
echo "and also enables it as a Bluetooth client for other devices (e.g., speakers, headphones)."
echo "A backup of your current configuration will be created in $CONFIG_BACKUP_DIR"

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi

# Create backup directory if not exists
mkdir -p "$CONFIG_BACKUP_DIR"

echo "=== Backing up current configuration... ==="
cp -r /etc/bluetooth "$CONFIG_BACKUP_DIR"
cp "$HID_SERVICE" "$CONFIG_BACKUP_DIR/jadeai-hid.service.bak" 2>/dev/null || true
cp "$HID_SCRIPT" "$CONFIG_BACKUP_DIR/bluetooth_hid.py.bak" 2>/dev/null || true
cp "$SDP_FILE" "$CONFIG_BACKUP_DIR/hid_sdp.xml.bak" 2>/dev/null || true
echo "Backup completed."

echo "=== Installing required packages... ==="
apt-get update
apt-get install -y bluetooth bluez bluez-tools python3-dbus python3-gi

echo "=== Enabling Bluetooth service... ==="
systemctl enable bluetooth
systemctl start bluetooth

echo "=== Configuring Bluetooth for HID Mode ==="
cat > "$BLUEZ_CONF" <<EOL
[General]
Name = JadeAI HID
Class = 0x002540  # HID Keyboard + Mouse
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

echo "=== Creating HID Service Record (SDP) ==="
mkdir -p /opt/jadeai
cat > "$SDP_FILE" <<EOL
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
      </sequence>
    </sequence>
  </attribute>
  <attribute id="0x0006">
    <sequence>
      <uint16 value="0x0100"/>
    </sequence>
  </attribute>
</record>
EOL

echo "=== Creating HID Python Script ==="
cat > "$HID_SCRIPT" <<EOL
#!/usr/bin/env python3
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

class BluetoothHID(dbus.service.Object):
    def __init__(self):
        bus = dbus.SystemBus()
        dbus.service.Object.__init__(self, bus, "/org/bluez/hid")
        self.mainloop = GLib.MainLoop()

    @dbus.service.method("org.bluez.Profile1", in_signature="oha{sv}", out_signature="")
    def NewConnection(self, device, fd, properties):
        print("New connection from:", device)

    @dbus.service.method("org.bluez.Profile1", in_signature="", out_signature="")
    def Release(self):
        print("Profile released")

    def register_hid_device(self):
        bus = dbus.SystemBus()
        manager = dbus.Interface(
            bus.get_object("org.bluez", "/org/bluez"),
            "org.bluez.ProfileManager1"
        )
        profile_path = "/org/bluez/hid"
        options = {
            "ServiceRecord": open("$SDP_FILE").read(),
            "Role": "server",
            "RequireAuthentication": False,
            "RequireAuthorization": False,
            "AutoConnect": True,
        }
        manager.RegisterProfile(profile_path, "00001124-0000-1000-8000-00805f9b34fb", options)
        print("HID Profile registered")

    def run(self):
        self.register_hid_device()
        print("HID Service running...")
        self.mainloop.run()

if __name__ == "__main__":
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    hid = BluetoothHID()
    hid.run()
EOL

chmod +x "$HID_SCRIPT"

echo "=== Creating systemd service for HID ==="
cat > "$HID_SERVICE" <<EOL
[Unit]
Description=JadeAI Bluetooth HID Service
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $HID_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable jadeai-hid
systemctl start jadeai-hid

echo "=== Enabling Bluetooth Client Mode ==="
bluetoothctl <<EOF
power on
discoverable on
pairable on
agent on
default-agent
EOF

echo "=== Bluetooth Dual Mode Setup Completed! ==="
echo "Device is now visible as 'JadeAI HID' and can also connect as a Bluetooth client."
echo "Use 'bluetoothctl' to manage connections."

# Restore function
restore_config() {
    echo "=== Restoring previous configuration... ==="
    cp -r "$CONFIG_BACKUP_DIR/bluetooth" /etc/
    cp "$CONFIG_BACKUP_DIR/jadeai-hid.service.bak" "$HID_SERVICE" 2>/dev/null || true
    cp "$CONFIG_BACKUP_DIR/bluetooth_hid.py.bak" "$HID_SCRIPT" 2>/dev/null || true
    cp "$CONFIG_BACKUP_DIR/hid_sdp.xml.bak" "$SDP_FILE" 2>/dev/null || true
    systemctl daemon-reload
    systemctl restart bluetooth
    systemctl restart jadeai-hid
    echo "=== Configuration restored! ==="
}

if [[ "$1" == "--restore" ]]; then
    restore_config
fi
