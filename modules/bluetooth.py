from flask import Blueprint, jsonify, request
import subprocess
import threading
import time
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

bluetooth_bp = Blueprint('bluetooth', __name__)

# Global variables
is_scanning = False
scan_thread = None
mainloop = None
bus = None

def init_dbus():
    """Initialize D-Bus connection."""
    global mainloop, bus
    DBusGMainLoop(set_as_default=True)
    mainloop = GLib.MainLoop()
    bus = dbus.SystemBus()

def get_bluetooth_interface():
    """Get the BlueZ interface."""
    obj = bus.get_object('org.bluez', '/')
    return dbus.Interface(obj, 'org.freedesktop.DBus.ObjectManager')

def execute_bluetooth_command(command):
    """Execute a bluetoothctl command and return its output."""
    try:
        process = subprocess.Popen(
            ['bluetoothctl'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        output, error = process.communicate(input=command)
        if error:
            print(f"Bluetooth command error: {error}")
        return output
    except Exception as e:
        print(f"Error executing bluetooth command: {str(e)}")
        return None

def scan_for_devices():
    """Scan for available Bluetooth devices."""
    global is_scanning
    try:
        # Configure Bluetooth
        commands = """power on
discoverable on
pairable on
agent on
default-agent
scan on
"""
        execute_bluetooth_command(commands)
        is_scanning = True
        
        # Scan for 30 seconds
        time.sleep(30)
        
        # Stop scanning
        execute_bluetooth_command("scan off")
    finally:
        is_scanning = False

def get_device_type(mac_address):
    """Get the type of Bluetooth device based on its class."""
    try:
        output = subprocess.check_output(['bluetoothctl', 'info', mac_address]).decode()
        if 'Class: 0x0005c0' in output:
            return 'combo'  # Combined keyboard/mouse HID device
        elif 'Class: 0x000540' in output:
            return 'keyboard'
        elif 'Class: 0x000580' in output:
            return 'mouse'
        return 'unknown'
    except Exception:
        return 'unknown'

@bluetooth_bp.route('/devices/paired')
def get_paired_devices():
    """Get list of paired Bluetooth devices."""
    try:
        output = subprocess.check_output(['bluetoothctl', 'paired-devices']).decode()
        devices = []
        for line in output.split('\n'):
            if line.strip():
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    mac = parts[1]
                    devices.append({
                        'mac': mac,
                        'name': parts[2],
                        'type': get_device_type(mac)
                    })
        return jsonify(devices)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@bluetooth_bp.route('/devices/available')
def get_available_devices():
    """Get list of available Bluetooth devices."""
    try:
        output = subprocess.check_output(['bluetoothctl', 'devices']).decode()
        devices = []
        for line in output.split('\n'):
            if line.strip():
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    mac = parts[1]
                    devices.append({
                        'mac': mac,
                        'name': parts[2],
                        'type': get_device_type(mac)
                    })
        return jsonify(devices)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@bluetooth_bp.route('/scan', methods=['POST'])
def start_scan():
    """Start Bluetooth device scanning."""
    global scan_thread, is_scanning
    
    if is_scanning:
        return jsonify({'message': 'Scan already in progress'}), 409
    
    scan_thread = threading.Thread(target=scan_for_devices)
    scan_thread.start()
    return jsonify({'message': 'Scan started'})

@bluetooth_bp.route('/scan/status')
def scan_status():
    """Check scanning status."""
    return jsonify({'scanning': is_scanning})

@bluetooth_bp.route('/pair', methods=['POST'])
def pair_device():
    """Pair with a Bluetooth device."""
    data = request.get_json()
    mac = data.get('mac')
    if not mac:
        return jsonify({'error': 'MAC address required'}), 400
    
    try:
        # Get device type before pairing
        device_type = get_device_type(mac)
        
        # Configure Bluetooth for pairing
        commands = f"""power on
agent on
default-agent
discoverable on
pairable on
pair {mac}
trust {mac}
connect {mac}
"""
        # Set appropriate class based on device type
        if device_type == 'combo':
            commands += f"hciconfig hci0 class 0x0005C0\n"
        elif device_type == 'keyboard':
            commands += f"hciconfig hci0 class 0x000540\n"
        elif device_type == 'mouse':
            commands += f"hciconfig hci0 class 0x000580\n"
        output = execute_bluetooth_command(commands)
        
        # Check if device is now paired
        paired_devices = subprocess.check_output(['bluetoothctl', 'paired-devices']).decode()
        if mac in paired_devices:
            return jsonify({'success': True})
        else:
            return jsonify({'error': f'Failed to pair device. Output: {output}'}), 500
            
    except Exception as e:
        return jsonify({'error': f'Failed to pair device: {str(e)}'}), 500

@bluetooth_bp.route('/unpair', methods=['POST'])
def unpair_device():
    """Unpair a Bluetooth device."""
    data = request.get_json()
    mac = data.get('mac')
    if not mac:
        return jsonify({'error': 'MAC address required'}), 400
    
    try:
        commands = f"""remove {mac}
"""
        execute_bluetooth_command(commands)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': f'Failed to unpair device: {str(e)}'}), 500

@bluetooth_bp.route('/discoverable', methods=['POST'])
def set_discoverable():
    """Set device discoverable status."""
    data = request.get_json()
    enabled = data.get('enabled', False)
    
    try:
        command = f"""discoverable {'on' if enabled else 'off'}
"""
        execute_bluetooth_command(command)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': f'Failed to set discoverable: {str(e)}'}), 500

@bluetooth_bp.route('/pairable', methods=['POST'])
def set_pairable():
    """Set device pairable status."""
    data = request.get_json()
    enabled = data.get('enabled', False)
    
    try:
        command = f"""pairable {'on' if enabled else 'off'}
"""
        execute_bluetooth_command(command)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': f'Failed to set pairable: {str(e)}'}), 500

# Initialize D-Bus when the module loads
init_dbus()
