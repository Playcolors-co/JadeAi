# JadeAI - AI-Powered KVM Assistant

## 🚀 Overview
JadeAI is an advanced AI-powered KVM (Keyboard, Video, Mouse) assistant designed to provide real-time assistance and automation on a remote computer. It acts as a **USB & Bluetooth HID device**, enabling AI-driven control of mouse and keyboard while analyzing the video feed from the connected machine.

### 🎯 Key Features
- **🖥️ AI-powered KVM** – JadeAI functions as a smart USB keyboard/mouse, controllable manually or via AI.
- **🎥 Real-time Video Processing** – Captures HDMI-to-USB input and analyzes it using AI.
- **🧠 Local & Cloud AI Assistance** – Runs optimized models like Mistral, LLaMA, and Phi-2 locally or connects to external AI APIs (OpenAI, Anthropic, OpenRouter, Azure ML, etc.).
- **🎙️ Voice Command & Response** – Always-on voice recognition and AI-driven speech synthesis.
- **🔵 Bluetooth HID Emulation** – Controls the remote computer wirelessly if needed.
- **📊 On-screen Overlay or Web App** – Displays AI suggestions via HDMI overlay or companion app.
- **🌐 Web-based Admin Interface** – Allows configuration of AI models (local/cloud), user settings, and system monitoring.

## 🛠️ Tech Stack
### Hardware
- **Raspberry Pi 5** (with **Hailo-8 TPU** for AI acceleration) or **Jetson Orin Nano**
- HDMI-to-USB capture card
- USB keyboard and mouse (optional)
- Microphone for voice commands

### Software
- **AI Frameworks**: `llama.cpp`, `Ollama`, `ONNX`, `TensorRT`
- **Cloud AI APIs**: OpenAI, Anthropic, OpenRouter, Azure ML (configurable via web admin)
- **Video Processing**: `OpenCV`, `GStreamer`
- **Object Detection**: `YOLOv8` optimized for `Hailo-8`
- **Speech Processing**: `Whisper.cpp` (speech recognition), `Coqui TTS` (text-to-speech)
- **HID Control**: `libcomposite`, `pybluez`, `hid-tools`
- **Web Admin Interface**: `Flask`, `React`, `WebSockets`

---

## 📦 Installation
### 1️⃣ Set Up USB & Bluetooth HID
Enable HID mode on Raspberry Pi:
```bash
sudo modprobe libcomposite
```
Install `hid-tools`:
```bash
sudo apt install hid-tools
```
Enable Bluetooth HID:
```bash
sudo systemctl enable bluetooth
```

### 2️⃣ Install AI Models & Dependencies
Clone the repository and install dependencies:
```bash
git clone https://github.com/your-repo/jadeai.git
cd jadeai
pip install -r requirements.txt
```

Download and optimize an LLM model (Mistral, LLaMA, or Phi-2) using `llama.cpp`:
```bash
mkdir models && cd models
wget <model-url>
```

### 3️⃣ Enable Video Processing & Object Detection
Install YOLOv8 and OpenCV:
```bash
pip install ultralytics opencv-python
```

### 4️⃣ Configure Web-based Admin Panel
Run the Flask-based web interface:
```bash
python web_admin.py
```
- Open the admin interface in a browser: `http://localhost:5000`
- Configure AI backend (local or cloud-based models)
- Monitor system performance and logs

### 5️⃣ Start JadeAI
Run the AI assistant:
```bash
python jadeai.py
```

---

## 🎮 Usage
1. **Connect JadeAI** via USB to your target machine.
2. **Run the AI assistant**, which will:
   - Process the HDMI video feed.
   - Suggest actions via voice output.
   - Accept manual or AI-driven control.
3. **Use voice commands** to interact with JadeAI.
4. **Configure AI preferences via the web admin interface**.
5. **Control your machine manually** or let AI assist you in decision-making.

---

## 📌 Roadmap
- [ ] Optimize inference speed for real-time AI decisions
- [ ] Improve speech recognition and natural language understanding
- [ ] Add custom user profiles for adaptive learning
- [ ] Enhance web admin panel with real-time AI control options

---

## 🤝 Contributing
Feel free to submit PRs or open issues if you'd like to contribute to the project.

---

## 📜 License
MIT License - free to use and modify.

---

## 📞 Contact
For questions or support, contact **Emanuele** or open a GitHub issue.

---

**JadeAI - Bringing AI-driven automation to your desktop!** 🚀
