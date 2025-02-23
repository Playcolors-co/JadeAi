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

if __name__ == '__main__':
    socketio.run(app, debug=True, host='0.0.0.0', port=5001)
