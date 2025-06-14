# JadeAI

A Bluetooth-based HID solution split into two containers:

- `jadeai-hid-bt`: exposes the host's Bluetooth interface as a GATT HID device (keyboard + mouse) with a REST API.
- `jadeai-hid-agent`: AI agent that sends HID commands to the HID server based on high-level instructions.
  
## 🧱 Project Structure

JadeAI_Vx.x/

├── hid-bt/

│ ├── Dockerfile

│ ├── main.c

│ ├── bt_manager.py

│ ├── api_server.py

│ ├── hid_report_map.h

│ ├── openapi.yaml

│ ├── requirements.txt

│ └── Makefile

├── hid-agent/

│ ├── Dockerfile

│ ├── agent.py

│ ├── supervisor_client.py

│ └── requirements.txt

├── docker-compose.yaml

└── README.md
