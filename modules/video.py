from flask import Blueprint, jsonify, request, Response
import cv2
import threading
import time
import subprocess
import os
from pathlib import Path

video_bp = Blueprint('video', __name__)

# Global variables
camera = None
frame = None
frame_lock = threading.Lock()
stream_thread = None
is_streaming = False

def get_video_devices():
    """Get list of available video devices."""
    devices = []
    try:
        for i in range(10):
            device_path = f'/dev/video{i}'
            if Path(device_path).exists():
                # Get device info using v4l2-ctl
                try:
                    info = subprocess.check_output(['v4l2-ctl', '--device', device_path, '--info']).decode()
                    name = next((line.split(':')[1].strip() for line in info.split('\n') 
                               if 'Card type' in line), f'Video Device {i}')
                    devices.append({
                        'id': i,
                        'path': device_path,
                        'name': name
                    })
                except:
                    devices.append({
                        'id': i,
                        'path': device_path,
                        'name': f'Video Device {i}'
                    })
    except Exception as e:
        print(f"Error getting video devices: {str(e)}")
    return devices

def init_camera(device_id=0):
    """Initialize the camera capture."""
    global camera
    try:
        if camera is not None:
            camera.release()
        camera = cv2.VideoCapture(device_id)
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
        return camera.isOpened()
    except Exception as e:
        print(f"Error initializing camera: {str(e)}")
        return False

def capture_frames():
    """Capture frames from the camera."""
    global frame, is_streaming
    while is_streaming and camera is not None:
        try:
            success, new_frame = camera.read()
            if success:
                with frame_lock:
                    frame = new_frame
            else:
                time.sleep(0.1)
        except Exception as e:
            print(f"Error capturing frame: {str(e)}")
            time.sleep(0.1)

def generate_frames():
    """Generate MJPEG frames for streaming."""
    global frame
    while True:
        with frame_lock:
            if frame is not None:
                try:
                    # Encode frame as JPEG
                    _, buffer = cv2.imencode('.jpg', frame)
                    frame_bytes = buffer.tobytes()
                    
                    # Yield the frame in MJPEG format
                    yield (b'--frame\r\n'
                           b'Content-Type: image/jpeg\r\n\r\n' + frame_bytes + b'\r\n')
                except Exception as e:
                    print(f"Error encoding frame: {str(e)}")
        time.sleep(0.033)  # ~30 FPS

@video_bp.route('/devices')
def list_devices():
    """List available video devices."""
    devices = get_video_devices()
    return jsonify(devices)

@video_bp.route('/start', methods=['POST'])
def start_capture():
    """Start video capture."""
    global stream_thread, is_streaming
    
    data = request.get_json()
    device_id = data.get('device_id', 0)
    
    if is_streaming:
        return jsonify({'error': 'Stream already running'}), 409
        
    if init_camera(device_id):
        is_streaming = True
        stream_thread = threading.Thread(target=capture_frames)
        stream_thread.start()
        return jsonify({'success': True})
    return jsonify({'error': 'Failed to initialize camera'}), 500

@video_bp.route('/stop', methods=['POST'])
def stop_capture():
    """Stop video capture."""
    global camera, is_streaming, stream_thread
    
    is_streaming = False
    if stream_thread:
        stream_thread.join()
    if camera:
        camera.release()
        camera = None
    return jsonify({'success': True})

@video_bp.route('/stream')
def video_stream():
    """Stream video feed."""
    if not is_streaming:
        return jsonify({'error': 'Stream not started'}), 400
    return Response(
        generate_frames(),
        mimetype='multipart/x-mixed-replace; boundary=frame'
    )

@video_bp.route('/snapshot')
def take_snapshot():
    """Take a snapshot from the video feed."""
    global frame
    if not is_streaming:
        return jsonify({'error': 'Stream not started'}), 400
        
    with frame_lock:
        if frame is not None:
            try:
                # Save snapshot to file
                timestamp = time.strftime('%Y%m%d-%H%M%S')
                filename = f'snapshot-{timestamp}.jpg'
                filepath = os.path.join('data', 'snapshots', filename)
                os.makedirs(os.path.dirname(filepath), exist_ok=True)
                cv2.imwrite(filepath, frame)
                return jsonify({
                    'success': True,
                    'filename': filename,
                    'path': filepath
                })
            except Exception as e:
                return jsonify({'error': f'Failed to save snapshot: {str(e)}'}), 500
        return jsonify({'error': 'No frame available'}), 404

@video_bp.route('/status')
def get_status():
    """Get video capture status."""
    return jsonify({
        'streaming': is_streaming,
        'camera_initialized': camera is not None and camera.isOpened() if camera else False,
        'devices': get_video_devices()
    })

# Clean up resources when the module is unloaded
def cleanup():
    global camera, is_streaming
    is_streaming = False
    if camera:
        camera.release()
        camera = None

# Register cleanup handler
import atexit
atexit.register(cleanup)
