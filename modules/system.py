from flask import Blueprint, jsonify, request
import subprocess
import os
import psutil
import json
from pathlib import Path

system_bp = Blueprint('system', __name__)

def get_system_info():
    """Get general system information."""
    try:
        # CPU info
        cpu_info = {
            'usage_percent': psutil.cpu_percent(interval=1),
            'count': psutil.cpu_count(),
            'frequency': psutil.cpu_freq()._asdict() if psutil.cpu_freq() else {},
            'temperature': get_cpu_temperature()
        }
        
        # Memory info
        memory = psutil.virtual_memory()
        memory_info = {
            'total': memory.total,
            'available': memory.available,
            'used': memory.used,
            'percent': memory.percent
        }
        
        # Disk info
        disk = psutil.disk_usage('/')
        disk_info = {
            'total': disk.total,
            'used': disk.used,
            'free': disk.free,
            'percent': disk.percent
        }
        
        return {
            'cpu': cpu_info,
            'memory': memory_info,
            'disk': disk_info,
            'uptime': get_uptime()
        }
    except Exception as e:
        print(f"Error getting system info: {str(e)}")
        return {}

def get_cpu_temperature():
    """Get CPU temperature."""
    try:
        temp_file = '/sys/class/thermal/thermal_zone0/temp'
        if os.path.exists(temp_file):
            with open(temp_file, 'r') as f:
                temp = float(f.read().strip()) / 1000.0
                return temp
    except Exception as e:
        print(f"Error getting CPU temperature: {str(e)}")
    return None

def get_uptime():
    """Get system uptime."""
    try:
        return psutil.boot_time()
    except Exception as e:
        print(f"Error getting uptime: {str(e)}")
        return None

def get_config():
    """Get system configuration."""
    config_file = Path('config/system.json')
    if config_file.exists():
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error reading config: {str(e)}")
    return {}

def save_config(config):
    """Save system configuration."""
    config_file = Path('config/system.json')
    try:
        os.makedirs(config_file.parent, exist_ok=True)
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except Exception as e:
        print(f"Error saving config: {str(e)}")
        return False

@system_bp.route('/info')
def system_info():
    """Get system information."""
    return jsonify(get_system_info())

@system_bp.route('/config', methods=['GET', 'POST'])
def system_config():
    """Get or update system configuration."""
    if request.method == 'GET':
        return jsonify(get_config())
    else:
        config = request.get_json()
        if save_config(config):
            return jsonify({'success': True})
        return jsonify({'error': 'Failed to save configuration'}), 500

@system_bp.route('/reboot', methods=['POST'])
def reboot_system():
    """Reboot the system."""
    try:
        subprocess.run(['sudo', 'reboot'])
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': f'Failed to reboot: {str(e)}'}), 500

@system_bp.route('/shutdown', methods=['POST'])
def shutdown_system():
    """Shutdown the system."""
    try:
        subprocess.run(['sudo', 'shutdown', '-h', 'now'])
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': f'Failed to shutdown: {str(e)}'}), 500

@system_bp.route('/logs')
def get_logs():
    """Get system logs."""
    try:
        # Get last 100 lines of system log
        output = subprocess.check_output(['tail', '-n', '100', '/var/log/syslog']).decode()
        logs = output.split('\n')
        return jsonify({'logs': logs})
    except Exception as e:
        return jsonify({'error': f'Failed to get logs: {str(e)}'}), 500

@system_bp.route('/update', methods=['POST'])
def update_system():
    """Update system packages."""
    try:
        # Update package list
        subprocess.run(['sudo', 'apt-get', 'update'], check=True)
        # Upgrade packages
        subprocess.run(['sudo', 'apt-get', 'upgrade', '-y'], check=True)
        return jsonify({'success': True})
    except subprocess.CalledProcessError as e:
        return jsonify({'error': f'Update failed: {str(e)}'}), 500

@system_bp.route('/services')
def get_services():
    """Get status of important services."""
    services = ['bluetooth', 'networking', 'ssh']
    status = {}
    
    for service in services:
        try:
            result = subprocess.run(['systemctl', 'is-active', service], 
                                  capture_output=True, text=True)
            status[service] = result.stdout.strip()
        except Exception as e:
            status[service] = 'unknown'
            
    return jsonify(status)

@system_bp.route('/service/control', methods=['POST'])
def control_service():
    """Control a system service."""
    data = request.get_json()
    service = data.get('service')
    action = data.get('action')  # start, stop, restart
    
    if not service or not action:
        return jsonify({'error': 'Service and action required'}), 400
        
    if action not in ['start', 'stop', 'restart']:
        return jsonify({'error': 'Invalid action'}), 400
        
    try:
        subprocess.run(['sudo', 'systemctl', action, service], check=True)
        return jsonify({'success': True})
    except subprocess.CalledProcessError as e:
        return jsonify({'error': f'Service control failed: {str(e)}'}), 500

@system_bp.route('/backup', methods=['POST'])
def create_backup():
    """Create a system backup."""
    try:
        timestamp = subprocess.check_output(['date', '+%Y%m%d-%H%M%S']).decode().strip()
        backup_dir = Path('data/backups')
        backup_dir.mkdir(parents=True, exist_ok=True)
        
        # Create backup of important directories
        backup_file = backup_dir / f'backup-{timestamp}.tar.gz'
        subprocess.run([
            'sudo', 'tar', 'czf', str(backup_file),
            '/etc/network/interfaces',
            '/etc/bluetooth',
            'config/',
            'data/'
        ], check=True)
        
        return jsonify({
            'success': True,
            'file': str(backup_file)
        })
    except Exception as e:
        return jsonify({'error': f'Backup failed: {str(e)}'}), 500

@system_bp.route('/restore', methods=['POST'])
def restore_backup():
    """Restore from a backup."""
    data = request.get_json()
    backup_file = data.get('file')
    
    if not backup_file:
        return jsonify({'error': 'Backup file required'}), 400
        
    try:
        # Extract backup
        subprocess.run(['sudo', 'tar', 'xzf', backup_file, '-C', '/'], check=True)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': f'Restore failed: {str(e)}'}), 500
