from flask import Blueprint, jsonify, request
import subprocess
import os
import time
import threading
from pathlib import Path

hid_bp = Blueprint('hid', __name__)

# HID device path
HID_DEVICE = '/dev/hidg0'

# Key mapping for HID keyboard
KEY_MAPPING = {
    'a': 0x04, 'b': 0x05, 'c': 0x06, 'd': 0x07,
    'e': 0x08, 'f': 0x09, 'g': 0x0a, 'h': 0x0b,
    'i': 0x0c, 'j': 0x0d, 'k': 0x0e, 'l': 0x0f,
    'm': 0x10, 'n': 0x11, 'o': 0x12, 'p': 0x13,
    'q': 0x14, 'r': 0x15, 's': 0x16, 't': 0x17,
    'u': 0x18, 'v': 0x19, 'w': 0x1a, 'x': 0x1b,
    'y': 0x1c, 'z': 0x1d, ' ': 0x2c,
    '1': 0x1e, '2': 0x1f, '3': 0x20, '4': 0x21,
    '5': 0x22, '6': 0x23, '7': 0x24, '8': 0x25,
    '9': 0x26, '0': 0x27,
    '\n': 0x28, '\t': 0x2b, '-': 0x2d, '=': 0x2e,
    '[': 0x2f, ']': 0x30, '\\': 0x31, ';': 0x33,
    "'": 0x34, '`': 0x35, ',': 0x36, '.': 0x37,
    '/': 0x38
}

# Modifier keys
MODIFIERS = {
    'SHIFT': 0x02,
    'CTRL': 0x01,
    'ALT': 0x04,
    'GUI': 0x08
}

# Mouse button mapping
MOUSE_BUTTONS = {
    'left': 0x01,
    'right': 0x02,
    'middle': 0x04
}

def setup_hid_device():
    """Set up the combined HID device if it doesn't exist."""
    if not Path(HID_DEVICE).exists():
        try:
            # Load required modules
            subprocess.run(['modprobe', 'libcomposite'])
            subprocess.run(['modprobe', 'usb_f_hid'])
            
            # Configure USB gadget
            gadget_path = '/sys/kernel/config/usb_gadget/hidcombo'
            os.makedirs(gadget_path, exist_ok=True)
            
            # Write USB device configuration
            with open(f'{gadget_path}/idVendor', 'w') as f:
                f.write('0x1d6b')  # Linux Foundation
            with open(f'{gadget_path}/idProduct', 'w') as f:
                f.write('0x0106')  # Multifunction Composite Gadget
            
            # Create English strings
            os.makedirs(f'{gadget_path}/strings/0x409', exist_ok=True)
            with open(f'{gadget_path}/strings/0x409/manufacturer', 'w') as f:
                f.write('Jade AI')
            with open(f'{gadget_path}/strings/0x409/product', 'w') as f:
                f.write('Jade AI HID')
            
            # Create HID function
            os.makedirs(f'{gadget_path}/functions/hid.usb0', exist_ok=True)
            with open(f'{gadget_path}/functions/hid.usb0/protocol', 'w') as f:
                f.write('0')  # No specific protocol for combo device
            with open(f'{gadget_path}/functions/hid.usb0/subclass', 'w') as f:
                f.write('0')  # No subclass for combo device
            with open(f'{gadget_path}/functions/hid.usb0/report_length', 'w') as f:
                f.write('12')  # 8 bytes for keyboard + 4 bytes for mouse
            
            # Write combined HID report descriptor
            report_desc = [
                # Keyboard descriptor
                0x05, 0x01,  # Usage Page (Generic Desktop)
                0x09, 0x06,  # Usage (Keyboard)
                0xa1, 0x01,  # Collection (Application)
                0x05, 0x07,  # Usage Page (Key Codes)
                0x19, 0xe0,  # Usage Minimum (224)
                0x29, 0xe7,  # Usage Maximum (231)
                0x15, 0x00,  # Logical Minimum (0)
                0x25, 0x01,  # Logical Maximum (1)
                0x75, 0x01,  # Report Size (1)
                0x95, 0x08,  # Report Count (8)
                0x81, 0x02,  # Input (Data, Variable, Absolute)
                0x95, 0x01,  # Report Count (1)
                0x75, 0x08,  # Report Size (8)
                0x81, 0x03,  # Input (Constant)
                0x95, 0x06,  # Report Count (6)
                0x75, 0x08,  # Report Size (8)
                0x15, 0x00,  # Logical Minimum (0)
                0x25, 0x65,  # Logical Maximum (101)
                0x05, 0x07,  # Usage Page (Key Codes)
                0x19, 0x00,  # Usage Minimum (0)
                0x29, 0x65,  # Usage Maximum (101)
                0x81, 0x00,  # Input (Data, Array)
                0xc0,        # End Collection
                
                # Mouse descriptor
                0x05, 0x01,  # Usage Page (Generic Desktop)
                0x09, 0x02,  # Usage (Mouse)
                0xa1, 0x01,  # Collection (Application)
                0x09, 0x01,  # Usage (Pointer)
                0xa1, 0x00,  # Collection (Physical)
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
                0x25, 0x7f,  # Logical Maximum (127)
                0x75, 0x08,  # Report Size (8)
                0x95, 0x03,  # Report Count (3)
                0x81, 0x06,  # Input (Data, Variable, Relative)
                0xc0,        # End Collection
                0xc0         # End Collection
            ]
            
            with open(f'{gadget_path}/functions/hid.usb0/report_desc', 'wb') as f:
                f.write(bytes(report_desc))
            
            # Create configuration
            os.makedirs(f'{gadget_path}/configs/c.1/strings/0x409', exist_ok=True)
            with open(f'{gadget_path}/configs/c.1/strings/0x409/configuration', 'w') as f:
                f.write('Config 1: HID Combo')
            
            # Link HID function to configuration
            os.symlink(
                f'{gadget_path}/functions/hid.usb0',
                f'{gadget_path}/configs/c.1/hid.usb0'
            )
            
            # Enable gadget
            with open('/sys/class/udc/1000480000.usb/UDC', 'r') as f:
                udc = f.read().strip()
            with open(f'{gadget_path}/UDC', 'w') as f:
                f.write(udc)
            
            # Create device node
            subprocess.run(['mknod', HID_DEVICE, 'c', '243', '0'])
            subprocess.run(['chmod', '666', HID_DEVICE])
            
            return True
        except Exception as e:
            print(f"Error setting up HID device: {str(e)}")
            return False
    return True

def send_keyboard_report(modifier=0, keys=[0,0,0,0,0,0]):
    """Send a keyboard HID report."""
    try:
        with open(HID_DEVICE, 'wb+') as fd:
            # First 8 bytes are keyboard report
            report = bytes([modifier] + [0] + keys + [0] * (6 - len(keys)))
            # Last 4 bytes are empty mouse report
            report += bytes([0, 0, 0, 0])
            fd.write(report)
            fd.flush()
        return True
    except Exception as e:
        print(f"Error sending keyboard report: {str(e)}")
        return False

def send_mouse_report(buttons=0, x=0, y=0, wheel=0):
    """Send a mouse HID report."""
    try:
        with open(HID_DEVICE, 'wb+') as fd:
            # First 8 bytes are empty keyboard report
            report = bytes([0] * 8)
            # Last 4 bytes are mouse report
            report += bytes([buttons, x & 0xff, y & 0xff, wheel & 0xff])
            fd.write(report)
            fd.flush()
        return True
    except Exception as e:
        print(f"Error sending mouse report: {str(e)}")
        return False

def send_key_event(key_code, modifier=0):
    """Send a key press and release event."""
    success = send_keyboard_report(modifier, [key_code])
    time.sleep(0.01)  # Brief delay between press and release
    success &= send_keyboard_report()  # Release all keys
    return success

def send_text(text, delay=0.1):
    """Send text through the virtual keyboard."""
    success = True
    for char in text:
        if char.isupper() or char in '!@#$%^&*()_+{}|:"<>?':
            # Use shift modifier for uppercase and special characters
            key_code = KEY_MAPPING.get(char.lower())
            if key_code:
                success &= send_key_event(key_code, MODIFIERS['SHIFT'])
        else:
            key_code = KEY_MAPPING.get(char)
            if key_code:
                success &= send_key_event(key_code)
        time.sleep(delay)
    return success

# API Routes

@hid_bp.route('/status')
def get_status():
    """Get HID device status."""
    return jsonify({
        'device_exists': os.path.exists(HID_DEVICE),
        'device_writable': os.access(HID_DEVICE, os.W_OK) if os.path.exists(HID_DEVICE) else False
    })

@hid_bp.route('/setup', methods=['POST'])
def setup_device():
    """Set up the virtual HID device."""
    if setup_hid_device():
        return jsonify({'success': True})
    return jsonify({'error': 'Failed to set up HID device'}), 500

@hid_bp.route('/keyboard/send', methods=['POST'])
def send_text_route():
    """Send text through the virtual keyboard."""
    data = request.get_json()
    text = data.get('text')
    delay = data.get('delay', 0.1)
    
    if not text:
        return jsonify({'error': 'Text required'}), 400
        
    if not os.path.exists(HID_DEVICE):
        if not setup_hid_device():
            return jsonify({'error': 'Failed to set up HID device'}), 500
            
    if send_text(text, delay):
        return jsonify({'success': True})
    return jsonify({'error': 'Failed to send text'}), 500

@hid_bp.route('/keyboard/type', methods=['POST'])
def type_key():
    """Type a single key with optional modifiers."""
    data = request.get_json()
    key = data.get('key')
    modifiers = data.get('modifiers', [])
    
    if not key:
        return jsonify({'error': 'Key required'}), 400
        
    if not os.path.exists(HID_DEVICE):
        if not setup_hid_device():
            return jsonify({'error': 'Failed to set up HID device'}), 500
            
    key_code = KEY_MAPPING.get(key.lower())
    if not key_code:
        return jsonify({'error': 'Invalid key'}), 400
        
    modifier_byte = 0
    for mod in modifiers:
        if mod.upper() in MODIFIERS:
            modifier_byte |= MODIFIERS[mod.upper()]
            
    if send_key_event(key_code, modifier_byte):
        return jsonify({'success': True})
    return jsonify({'error': 'Failed to send key event'}), 500

@hid_bp.route('/mouse/click', methods=['POST'])
def mouse_click():
    """Send a mouse button click."""
    data = request.get_json()
    button = data.get('button', 'left')
    
    if button not in MOUSE_BUTTONS:
        return jsonify({'error': 'Invalid button'}), 400
        
    if not os.path.exists(HID_DEVICE):
        if not setup_hid_device():
            return jsonify({'error': 'Failed to set up HID device'}), 500
    
    # Press button
    if send_mouse_report(MOUSE_BUTTONS[button]):
        time.sleep(0.1)  # Hold for 100ms
        # Release button
        if send_mouse_report(0):
            return jsonify({'success': True})
    
    return jsonify({'error': 'Failed to send mouse click'}), 500

@hid_bp.route('/mouse/move', methods=['POST'])
def mouse_move():
    """Move the mouse cursor."""
    data = request.get_json()
    x = data.get('x', 0)
    y = data.get('y', 0)
    relative = data.get('relative', True)
    
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        return jsonify({'error': 'Invalid coordinates'}), 400
    
    if not os.path.exists(HID_DEVICE):
        if not setup_hid_device():
            return jsonify({'error': 'Failed to set up HID device'}), 500
    
    # Ensure values are within valid range (-127 to 127)
    x = max(-127, min(127, int(x)))
    y = max(-127, min(127, int(y)))
    
    if send_mouse_report(0, x, y):
        return jsonify({'success': True})
    
    return jsonify({'error': 'Failed to move mouse'}), 500

@hid_bp.route('/mouse/scroll', methods=['POST'])
def mouse_scroll():
    """Scroll the mouse wheel."""
    data = request.get_json()
    amount = data.get('amount', 0)
    
    if not isinstance(amount, (int, float)):
        return jsonify({'error': 'Invalid scroll amount'}), 400
    
    if not os.path.exists(HID_DEVICE):
        if not setup_hid_device():
            return jsonify({'error': 'Failed to set up HID device'}), 500
    
    # Ensure value is within valid range (-127 to 127)
    amount = max(-127, min(127, int(amount)))
    
    if send_mouse_report(0, 0, 0, amount):
        return jsonify({'success': True})
    
    return jsonify({'error': 'Failed to scroll'}), 500

# Initialize HID device when module loads
setup_hid_device()
