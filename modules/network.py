from flask import Blueprint, jsonify, request
import subprocess
import netifaces
import NetworkManager
import json
import os

network_bp = Blueprint('network', __name__)

def get_interface_info(interface):
    """Get detailed information about a network interface."""
    try:
        addrs = netifaces.ifaddresses(interface)
        info = {
            'name': interface,
            'status': 'up' if netifaces.AF_INET in addrs else 'down',
            'type': 'wireless' if interface.startswith('wlan') else 'ethernet',
            'addresses': []
        }
        
        # Get IP addresses
        if netifaces.AF_INET in addrs:
            for addr in addrs[netifaces.AF_INET]:
                info['addresses'].append({
                    'ip': addr.get('addr'),
                    'netmask': addr.get('netmask'),
                    'broadcast': addr.get('broadcast')
                })
        
        # Get MAC address
        if netifaces.AF_LINK in addrs:
            info['mac'] = addrs[netifaces.AF_LINK][0]['addr']
            
        return info
    except Exception as e:
        print(f"Error getting interface info: {str(e)}")
        return None

def get_wifi_info():
    """Get information about WiFi connections."""
    try:
        wifi_devices = []
        for device in NetworkManager.NetworkManager.GetDevices():
            if device.DeviceType == NetworkManager.NM_DEVICE_TYPE_WIFI:
                wifi_devices.append({
                    'interface': device.Interface,
                    'active': device.State == NetworkManager.NM_DEVICE_STATE_ACTIVATED,
                    'connection': device.ActiveConnection.Connection.GetSettings()['connection']['id'] if device.ActiveConnection else None
                })
        return wifi_devices
    except Exception as e:
        print(f"Error getting WiFi info: {str(e)}")
        return []

@network_bp.route('/interfaces')
def get_interfaces():
    """Get all network interfaces."""
    interfaces = []
    for iface in netifaces.interfaces():
        info = get_interface_info(iface)
        if info:
            interfaces.append(info)
    return jsonify(interfaces)

@network_bp.route('/wifi/scan')
def scan_wifi():
    """Scan for available WiFi networks."""
    try:
        networks = []
        for device in NetworkManager.NetworkManager.GetDevices():
            if device.DeviceType == NetworkManager.NM_DEVICE_TYPE_WIFI:
                device.RequestScan({})
                for ap in device.GetAccessPoints():
                    networks.append({
                        'ssid': ap.Ssid,
                        'strength': ap.Strength,
                        'security': 'secured' if ap.WpaFlags or ap.RsnFlags else 'open',
                        'frequency': ap.Frequency
                    })
        return jsonify(networks)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@network_bp.route('/wifi/connect', methods=['POST'])
def connect_wifi():
    """Connect to a WiFi network."""
    data = request.get_json()
    ssid = data.get('ssid')
    password = data.get('password')
    
    if not ssid:
        return jsonify({'error': 'SSID required'}), 400
        
    try:
        # Find WiFi device
        wifi_dev = None
        for dev in NetworkManager.NetworkManager.GetDevices():
            if dev.DeviceType == NetworkManager.NM_DEVICE_TYPE_WIFI:
                wifi_dev = dev
                break
                
        if not wifi_dev:
            return jsonify({'error': 'No WiFi device found'}), 404
            
        # Find access point
        ap = None
        for access_point in wifi_dev.GetAccessPoints():
            if access_point.Ssid == ssid:
                ap = access_point
                break
                
        if not ap:
            return jsonify({'error': 'Access point not found'}), 404
            
        # Create connection settings
        settings = {
            'connection': {
                'id': ssid,
                'type': '802-11-wireless',
                'autoconnect': True
            },
            '802-11-wireless': {
                'ssid': ssid,
                'mode': 'infrastructure',
            }
        }
        
        if password:
            settings['802-11-wireless-security'] = {
                'key-mgmt': 'wpa-psk',
                'psk': password
            }
            
        # Add connection and activate it
        conn = NetworkManager.NetworkManager.AddConnection(settings)
        NetworkManager.NetworkManager.ActivateConnection(conn, wifi_dev, "/")
        
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@network_bp.route('/wifi/disconnect', methods=['POST'])
def disconnect_wifi():
    """Disconnect from a WiFi network."""
    data = request.get_json()
    ssid = data.get('ssid')
    
    if not ssid:
        return jsonify({'error': 'SSID required'}), 400
        
    try:
        # Find and delete connection
        for conn in NetworkManager.NetworkManager.GetConnections():
            if conn.GetSettings()['connection']['id'] == ssid:
                conn.Delete()
                return jsonify({'success': True})
                
        return jsonify({'error': 'Connection not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@network_bp.route('/lan/config', methods=['GET', 'POST'])
def configure_lan():
    """Get or set LAN configuration."""
    if request.method == 'GET':
        try:
            with open('/etc/network/interfaces', 'r') as f:
                config = f.read()
            return jsonify({'config': config})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    else:
        data = request.get_json()
        interface = data.get('interface')
        method = data.get('method', 'dhcp')
        settings = data.get('settings', {})
        
        if not interface:
            return jsonify({'error': 'Interface required'}), 400
            
        try:
            config = f"auto {interface}\niface {interface} inet {method}\n"
            if method == 'static':
                config += f"    address {settings.get('address', '')}\n"
                config += f"    netmask {settings.get('netmask', '')}\n"
                config += f"    gateway {settings.get('gateway', '')}\n"
                
            with open('/etc/network/interfaces', 'w') as f:
                f.write(config)
                
            # Restart networking
            subprocess.run(['systemctl', 'restart', 'networking'])
            
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

@network_bp.route('/status')
def get_status():
    """Get overall network status."""
    try:
        status = {
            'interfaces': [],
            'wifi': get_wifi_info(),
            'default_gateway': netifaces.gateways().get('default', {}).get(netifaces.AF_INET, [None])[0]
        }
        
        for iface in netifaces.interfaces():
            info = get_interface_info(iface)
            if info:
                status['interfaces'].append(info)
                
        return jsonify(status)
    except Exception as e:
        return jsonify({'error': str(e)}), 500
