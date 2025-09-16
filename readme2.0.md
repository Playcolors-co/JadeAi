# JadeAI • Repository Skeleton & README

## Vision
**JadeAI** is a fully local AI system designed to operate **between two computers**:
- **Input**: captures video from the **screen of another computer** using HDMI→USB capture (or Wi‑Fi streaming).
- **Output**: controls that same external computer through **HID emulation** (keyboard and mouse via Bluetooth or USB gadget), always in an assistive mode and never overriding the human user.

In essence, JadeAI observes an **external host computer** and interacts with it: the human remains in primary control, while JadeAI can assist with overlay actions such as clicks, typing, or hotkeys.

---

## Repository Structure
```
jadeai/
├── configs/
│   ├── perception.yaml
│   ├── planner.yaml
│   └── hid.yaml
│
├── services/
│   ├── gateway/
│   │   ├── Dockerfile
│   │   └── main.py
│   ├── perception/
│   │   ├── Dockerfile
│   │   └── detector.py
│   ├── llm/
│   │   ├── Dockerfile
│   │   └── server.py
│   ├── planner/
│   │   ├── Dockerfile
│   │   └── planner.py
│   ├── hid/
│   │   ├── Dockerfile
│   │   └── hid_server.py
│   ├── memory/
│   │   ├── Dockerfile
│   │   └── memory.py
│   └── bus/
│       ├── Dockerfile
│       └── bus.py
│
├── scripts/
│   ├── build.sh
│   ├── run.sh
│   └── stop.sh
│
├── tests/
│   ├── test_perception.py
│   ├── test_planner.py
│   └── test_hid.py
│
├── docker-compose.yml
├── docker-compose.profiles.yml
├── Makefile
└── README.md
```

---


## Repository Structure

```
JadeAI/
├─ README.md                      # Project overview (this file)
├─ LICENSE                        # Apache-2.0 
├─ .gitignore
├─ .env.example                   # Environment variables template
├─ Makefile                       # Common build/run/diagnostic targets
├─ docker-compose.yml             # Core multi-service stack
├─ docker-compose.profiles.yml    # Optional profiles (core/perception/llm/hid/bus)
├─ configs/
│  ├─ models.yml                  # Model backends, paths, quantisation
│  ├─ policy.yml                  # Guardrails, allow/deny lists, confirmations
│  ├─ perception.yml              # Detector/OCR thresholds, ROI, FPS caps
│  ├─ planner.yml                 # Timeouts, retries, heuristics
│  ├─ hid.yml                     # BT/USB mode, device name, rate limits
│  └─ telemetry.yml               # Logging & metrics config
├─ data/
│  ├─ samples/                    # Example frames & annotations
│  └─ cache/                      # Runtime caches (gitignored)
├─ docs/
│  ├─ ARCHITECTURE.md             # Deep dive into the agentic stack
│  ├─ MODELS.md                   # LLM/Vision/OCR setup on Jetson
│  ├─ API.md                      # OpenAPI/Endpoint reference
│  ├─ TRAINING.md                 # Fine-tuning detector + dataset notes
│  ├─ SAFETY.md                   # Safety policies & HCI guidelines
│  └─ ROADMAP.md                  # Milestones and timelines
├─ scripts/
│  ├─ jetson_bootstrap.sh         # JetPack checks, system packages
│  ├─ build_trt_engines.py        # Export ONNX → TensorRT (detector/OCR)
│  ├─ export_llm_gguf.sh          # Convert & quantise LLM to GGUF (llama.cpp)
│  ├─ export_llm_trtllm.sh        # Convert LLM to TensorRT-LLM engines
│  ├─ run_dev.sh                  # Convenience runner
│  └─ bench_*.py                  # Micro-benchmarks (OCR/detector/LLM)
├─ services/
│  ├─ gateway/
│  │  ├─ app/
│  │  │  ├─ main.py               # FastAPI entry, routers, WS streaming
│  │  │  ├─ deps.py               # Settings & dependency injection
│  │  │  ├─ routers/
│  │  │  │  ├─ health.py
│  │  │  │  ├─ perception.py
│  │  │  │  ├─ planner.py
│  │  │  │  ├─ actions.py         # Execute plans/steps
│  │  │  │  ├─ hid.py
│  │  │  │  └─ memory.py
│  │  │  └─ schemas/
│  │  │     ├─ scene.py           # SceneGraph, Element, BBox, OCRSpan
│  │  │     ├─ plan.py            # Plan, Step, Preconditions, Results
│  │  │     └─ events.py          # Bus messages
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ perception/
│  │  ├─ detector/                # YOLO/RT-DETR wrappers + TRT engines
│  │  ├─ ocr/                     # PaddleOCR/Tesseract wrappers
│  │  ├─ capture/                 # V4L2/ffmpeg frame grab & keyframe logic
│  │  ├─ annotate/                # Debug overlays
│  │  ├─ service.py               # REST/ZeroMQ/Redis endpoints
│  │  ├─ schemas.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ llm/
│  │  ├─ llama_cpp/               # llama.cpp server launcher & bindings
│  │  ├─ trt_llm/                 # TensorRT-LLM launcher & configs
│  │  ├─ prompts/                 # System & tool prompts
│  │  ├─ tool_calls.py            # JSON tool schema (click/type/…)
│  │  ├─ service.py               # Local LLM microservice (OpenAI compatible)
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ planner/
│  │  ├─ graph/                   # LangGraph/SM orchestration, nodes
│  │  ├─ tools/                   # Adapters to HID, Perception, Memory
│  │  ├─ policies/                # Safety checks, confirmations
│  │  ├─ service.py               # Plan APIs & execution loop
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ hid/
│  │  ├─ bt_gatt/                 # BlueZ/bluezero GATT HID server
│  │  ├─ usb_gadget/              # USB HID gadget device-mode scripts
│  │  ├─ api.py                   # FastAPI for /hid/* endpoints
│  │  ├─ descriptors/             # HID report maps (kbd+mouse+media)
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ memory/
│  │  ├─ vector/                  # FAISS/Chroma wrappers
│  │  ├─ store/                   # sqlite for recipes/playbooks
│  │  ├─ service.py               # RAG & persistence API
│  │  ├─ schemas.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  └─ ui/
│     ├─ web/
│     │  ├─ public/
│     │  ├─ src/
│     │  │  ├─ App.tsx            # Dashboard: frame preview, steps, controls
│     │  │  ├─ components/
│     │  │  └─ api/
│     │  ├─ package.json
│     │  └─ Dockerfile
│     └─ overlay/                 # Optional on‑screen overlay injector
├─ tests/
│  ├─ e2e/
│  ├─ services/
│  └─ fixtures/
└─ third_party/
   └─ licenses/
```

### .gitignore (excerpt)
```
# Python
__pycache__/
*.py[cod]
.venv/

# Models & engines
/models/
/data/cache/
*.engine
*.gguf

# Environment
.env
.env.*

# Node
node_modules/

# Docker
*.log
/dist/
```

### .env.example (excerpt)
```
JADEAI_DEVICE_NAME=JadeAI HID
JADEAI_HID_MODE=bluetooth          # or usb
JADEAI_CAPTURE_DEV=/dev/video0     # UVC from HDMI→USB grabber
JADEAI_RESOLUTION=1280x720
JADEAI_FPS=2
LLM_BACKEND=llama_cpp              # or trt_llm
LLM_MODEL_PATH=/models/llama3-8b-instruct.Q4_K_M.gguf
DETECTOR_ENGINE=/models/yolo_gui_n_int8.engine
OCR_MODEL_DIR=/models/paddleocr
BUS=redis://redis:6379
```

### Makefile (excerpt)
```makefile
.PHONY: doctor up down logs fmt test up-core up-perception up-bus

doctor:
	@scripts/jetson_bootstrap.sh --doctor

up:
	docker compose up -d --build

up-core:
	docker compose -f docker-compose.profiles.yml --profile core up -d --build

up-perception:
	docker compose -f docker-compose.profiles.yml --profile perception up -d --build perception

up-bus:
	docker compose -f docker-compose.profiles.yml --profile bus up -d --build redis

down:
	docker compose down

logs:
	docker compose logs -f --tail=200

fmt:
	ruff format || true

test:
	pytest -q
```

### docker-compose.yml (core excerpt)
```yaml
version: "3.9"
services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped

  gateway:
    build: ./services/gateway
    ports: ["8080:8080"]
    env_file: .env
    depends_on: [redis, perception, planner, llm, hid, memory]

  perception:
    build: ./services/perception
    runtime: nvidia
    env_file: .env
    devices:
      - ${JADEAI_CAPTURE_DEV}:${JADEAI_CAPTURE_DEV}
    volumes:
      - ./models:/models

  llm:
    build: ./services/llm
    runtime: nvidia
    env_file: .env
    volumes:
      - ./models:/models

  planner:
    build: ./services/planner
    env_file: .env

  hid:
    build: ./services/hid
    network_mode: host   # Bluetooth often needs host networking
    privileged: true     # USB gadget & bt management
    env_file: .env

  memory:
    build: ./services/memory
    volumes:
      - ./memory_store:/store
```

### Config snippets
`configs/models.yml`
```yaml
llm:
  backend: ${LLM_BACKEND}
  llama_cpp:
    model_path: ${LLM_MODEL_PATH}
    n_ctx: 4096
    n_gpu_layers: 999
    flash_attn: true
  trt_llm:
    engine_dir: /models/trt_llm/llama3_8b_int8
perception:
  detector_engine: ${DETECTOR_ENGINE}
  ocr_model_dir: ${OCR_MODEL_DIR}
```

`configs/policy.yml`
```yaml
confirm:
  destructive: true
  external_send: true  # email/send/payment
allow_apps:
  - settings
  - browser
block_patterns:
  - /delete|erase|format/i
```

`configs/perception.yml`
```yaml
fps: ${JADEAI_FPS}
resolution: ${JADEAI_RESOLUTION}
roi_padding: 4
ocr:
  languages: [en]
  min_conf: 0.6
```

---

## Modular Architecture

### 1. Ingest & Synchronisation
- Frame capture module (HDMI→USB) plus cursor tracking.
- Low frequency capture (e.g. 1–2 fps) to conserve resources on Jetson.
- Outputs keyframes with cursor coordinates.

### 2. Perception Agents
- Lightweight YOLOv8/11‑n detector for UI elements (buttons, icons, menus).
- PaddleOCR for text recognition in regions of interest.
- Scene graph builder (`SceneGraph`) to create a structured representation of the interface.

### 3. Understanding Agent (LLM)
- Local LLM (Mistral / Llama 3.1 7–8B quantised for Jetson).
- Input: serialised `SceneGraph`.
- Output: structured step‑by‑step plans with function‑calling.

### 4. Planner Agent
- Converts high‑level goals into atomic actions.
- Enforces **safety policies** (whitelists, human confirmations).
- Handles monitoring, error detection, and re‑planning.

### 5. Executor Agent (HID)
- Executes physical actions on the external computer:
  - mouse click/move
  - keyboard typing/hotkeys
- Exposed via REST API controlling a Bluetooth HID GATT server or USB gadget HID.

### 6. Memory & Tools
- Short‑ and long‑term context memory (FAISS/Chroma DB).
- Integration with fallback tools (system scripts, APIs).

### 7. Supervision & UI
- Local web dashboard (FastAPI + Vue/React) for:
  - system monitoring
  - human confirmations
  - activity logs and replay

---

## Containerisation & Deployment

### Services (dedicated Docker containers)
- **gateway**: REST API + UI proxy.
- **perception**: detection + OCR.
- **llm**: local model (OpenAI‑compatible API).
- **planner**: orchestration.
- **hid**: execution layer (Bluetooth HID/USB gadget).
- **memory**: retrieval‑augmented generation store.
- **bus**: optional messaging backbone (Redis/NATS).

### Compose with profiles
Defined in `docker-compose.profiles.yml`, enabling selective start‑up:
- `core`
- `perception`
- `llm`
- `hid`
- `bus`

### Minimal Dockerfiles
- **Perception**: YOLO + PaddleOCR
- **LLM**: llama.cpp / TensorRT‑LLM
- **HID**: BlueZ/pydbus REST server

### HID Requirements
- **Bluetooth**: `network_mode: host`, `privileged: true`, BlueZ access.
- **USB gadget**: Jetson kernel support required, run with `--privileged`.

---

## Security & Governance
- **Assistive mode** ensures user control is never pre‑empted.
- Critical actions require explicit confirmation.
- Centralised logging enables auditing and replay.

---

## MVP Delivery Checklist
- [ ] HDMI→USB capture at 1 fps exposed via `/perception/capture`
- [ ] Basic HID API endpoints: `/hid/click`, `/hid/text`
- [ ] Local quantised LLM (Q4‑K) converting scene→actions
- [ ] Planner with minimal safety policy
- [ ] Web UI with logging and confirmation mechanisms

---

## Roadmap
1. **MVP (2 weeks)**: capture → perception → planner → HID execution → web UI
2. **Iteration 2**: add memory and tools, JSON logging, Prometheus metrics
3. **Iteration 3**: introduce event bus, scale perception/planner modules
4. **Iteration 4**: add on‑screen overlay output to external host (OSD)

---

## Core Principle
Unlike a conventional “screen AI”, **JadeAI functions as an external observer and assistant**: it acquires **only video input from an external PC** and outputs **only HID commands back to that PC**, ensuring the human user always remains central to the interaction.

