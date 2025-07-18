from flask import Flask, request, jsonify
import subprocess
import bt_manager

app = Flask(__name__)

@app.route('/hid/text', methods=['POST'])
def type_text():
    text = request.json.get('text')
    subprocess.run(["./bthid", "type", text])
    return '', 204

@app.route('/hid/move', methods=['POST'])
def move_mouse():
    x = request.json.get('x')
    y = request.json.get('y')
    subprocess.run(["./bthid", "move", str(x), str(y)])
    return '', 204

@app.route('/hid/click', methods=['POST'])
def click():
    button = request.json.get('button', 'left')
    subprocess.run(["./bthid", "click", button])
    return '', 204

@app.route('/hid/status', methods=['GET'])
def status():
    return jsonify(bt_manager.get_status())

@app.route('/hid/disconnect', methods=['POST'])
def disconnect():
    bt_manager.disconnect()
    return '', 204

@app.route('/hid/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    bt_manager.setup_bluetooth()
    app.run(host='0.0.0.0', port=5001)
