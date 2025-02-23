from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit
import os

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration routes
@app.route('/api/config', methods=['GET'])
def get_config():
    # Mock configuration data
    config = {
        'ai_backend': 'local',
        'model': 'mistral',
        'api_keys': {
            'openai': '****',
            'anthropic': '****'
        },
        'system_status': {
            'cpu_usage': 45,
            'memory_usage': 60,
            'gpu_usage': 30
        },
        'system_settings': {
            'voice_commands': True,
            'auto_suggestions': True,
            'performance_mode': 'balanced'
        }
    }
    return jsonify(config)

@app.route('/api/config', methods=['POST'])
def update_config():
    new_config = request.json
    # Here you would actually save the configuration
    return jsonify({'status': 'success', 'message': 'Configuration updated'})

# Model management routes
@app.route('/api/models', methods=['GET'])
def get_models():
    # Mock model list
    models = [
        {'id': 'mistral', 'name': 'Mistral', 'type': 'local', 'status': 'active'},
        {'id': 'llama2', 'name': 'LLaMA-2', 'type': 'local', 'status': 'installed'},
        {'id': 'gpt4', 'name': 'GPT-4', 'type': 'cloud', 'status': 'available'},
        {'id': 'claude', 'name': 'Claude', 'type': 'cloud', 'status': 'available'}
    ]
    return jsonify(models)

# System monitoring
@socketio.on('connect')
def handle_connect():
    print('Client connected')

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')

def emit_system_stats():
    # Mock system statistics
    stats = {
        'cpu_usage': 45,
        'memory_usage': 60,
        'gpu_usage': 30,
        'active_model': 'mistral',
        'requests_per_minute': 12
    }
    socketio.emit('system_stats', stats)

# System monitoring routes
@app.route('/api/system/info', methods=['GET'])
def get_system_info():
    # Mock system information
    info = {
        'cpu': {
            'model': 'AMD Ryzen 9 5950X',
            'cores': 16,
            'usage': 45,
            'temperature': 65
        },
        'memory': {
            'total': 32 * 1024 * 1024 * 1024,  # 32GB in bytes
            'used': 16 * 1024 * 1024 * 1024,   # 16GB in bytes
            'free': 16 * 1024 * 1024 * 1024    # 16GB in bytes
        },
        'gpu': {
            'model': 'NVIDIA RTX 4090',
            'memory': {
                'total': 24 * 1024 * 1024 * 1024,  # 24GB in bytes
                'used': 8 * 1024 * 1024 * 1024     # 8GB in bytes
            },
            'temperature': 70
        },
        'storage': {
            'total': 1024 * 1024 * 1024 * 1024,  # 1TB in bytes
            'used': 512 * 1024 * 1024 * 1024,    # 512GB in bytes
            'free': 512 * 1024 * 1024 * 1024     # 512GB in bytes
        }
    }
    return jsonify(info)

@app.route('/api/system/logs', methods=['GET'])
def get_system_logs():
    # Mock system logs
    logs = [
        {
            'timestamp': '2025-02-23 15:00:00',
            'level': 'info',
            'message': 'System started successfully',
            'source': 'system'
        },
        {
            'timestamp': '2025-02-23 15:01:00',
            'level': 'info',
            'message': 'Loaded Mistral model',
            'source': 'model_manager'
        },
        {
            'timestamp': '2025-02-23 15:02:00',
            'level': 'warning',
            'message': 'High GPU memory usage detected',
            'source': 'resource_monitor'
        },
        {
            'timestamp': '2025-02-23 15:03:00',
            'level': 'error',
            'message': 'Failed to load LLaMA-2 model: insufficient memory',
            'source': 'model_manager'
        }
    ]
    return jsonify(logs)

if __name__ == '__main__':
    socketio.run(app, debug=True, host='0.0.0.0', port=5001)
