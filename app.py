#!/usr/bin/env python3
import os
import eventlet
eventlet.monkey_patch()

from flask import Flask, render_template
from flask_socketio import SocketIO
from dotenv import load_dotenv
import logging

# Import modules
from modules.bluetooth import bluetooth_bp
from modules.network import network_bp
from modules.hid import hid_bp
from modules.video import video_bp
from modules.system import system_bp

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables, with fallback values
if os.path.exists('.env'):
    load_dotenv()
else:
    logger.warning('.env file not found, using default values')

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'jade-ai-secret-key-2024')
socketio = SocketIO(app, async_mode='eventlet')

# Ensure directories exist with proper permissions
for directory in ['logs', 'data']:
    dir_path = os.path.join(os.getenv('DATA_DIR', '/app'), directory)
    os.makedirs(dir_path, mode=0o755, exist_ok=True)

# Register blueprints
app.register_blueprint(bluetooth_bp, url_prefix='/api/bluetooth')
app.register_blueprint(network_bp, url_prefix='/api/network')
app.register_blueprint(hid_bp, url_prefix='/api/hid')
app.register_blueprint(video_bp, url_prefix='/api/video')
app.register_blueprint(system_bp, url_prefix='/api/system')

@app.route('/')
def index():
    """Render the main application page."""
    return render_template('index.html')

@app.route('/bluetooth')
def bluetooth():
    """Render the bluetooth page."""
    return render_template('bluetooth.html')

@app.route('/network')
def network():
    """Render the network page."""
    return render_template('network.html')

@app.route('/hid-emulator')
def hid_emulator():
    """Render the HID emulator page."""
    return render_template('hid_emulator.html')

@app.route('/keyboard')
def keyboard():
    """Render the keyboard page."""
    return render_template('keyboard.html')

@app.route('/video')
def video():
    """Render the video page."""
    return render_template('video.html')

@app.route('/system')
def system():
    """Render the system page."""
    return render_template('system.html')

@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connection."""
    print('Client connected')

@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnection."""
    print('Client disconnected')

if __name__ == '__main__':
    try:
        port = int(os.getenv('PORT', 5000))
        logger.info(f'Starting application on port {port}')
        socketio.run(app, host='0.0.0.0', port=port, allow_unsafe_werkzeug=True)
    except Exception as e:
        logger.error(f'Failed to start application: {str(e)}')
        raise
