# JadeAI 2.0

JadeAI 2.0 is a fully local, modular agentic stack that observes an external host computer over HDMI capture and assists the
user via HID emulation. The project is designed to run on resource-constrained edge devices (Jetson Orin/Nano, x86 mini PCs) wh
ile keeping the human in control at all times.

---

## Vision

**Input** is the captured video stream from the external computer. **Output** is restricted to HID actions (keyboard, mouse,
hotkeys) that are executed only after policy checks and, when needed, explicit human confirmation. JadeAI never replaces the us
er; it provides contextual assistance.

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
│  ├─ bench_detector.py           # Micro-benchmark for detector pipeline
│  ├─ bench_ocr.py                # Micro-benchmark for OCR pipeline
│  └─ bench_llm.py                # Micro-benchmark for LLM inference
├─ services/
│  ├─ gateway/
│  │  ├─ app/
│  │  │  ├─ main.py               # FastAPI entry, routers, WS streaming
│  │  │  ├─ deps.py               # Settings & dependency injection
│  │  │  ├─ routers/
│  │  │  │  ├─ __init__.py
│  │  │  │  ├─ health.py
│  │  │  │  ├─ perception.py
│  │  │  │  ├─ planner.py
│  │  │  │  ├─ actions.py         # Execute plans/steps
│  │  │  │  ├─ hid.py
│  │  │  │  └─ memory.py
│  │  │  └─ schemas/
│  │  │     ├─ __init__.py
│  │  │     ├─ scene.py           # SceneGraph, Element, BBox, OCRSpan
│  │  │     ├─ plan.py            # Plan, Step, Preconditions, Results
│  │  │     └─ events.py          # Bus messages
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ perception/
│  │  ├─ detector/
│  │  ├─ ocr/
│  │  ├─ capture/
│  │  ├─ annotate/
│  │  ├─ service.py               # REST/ZeroMQ/Redis endpoints (stub)
│  │  ├─ schemas.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ llm/
│  │  ├─ server.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ planner/
│  │  ├─ planner.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ hid/
│  │  ├─ hid_server.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  ├─ memory/
│  │  ├─ memory.py
│  │  ├─ requirements.txt
│  │  └─ Dockerfile
│  └─ bus/
│     ├─ bus.py
│     ├─ requirements.txt
│     └─ Dockerfile
├─ tests/
│  ├─ test_perception.py
│  ├─ test_planner.py
│  └─ test_hid.py
└─ pyproject.toml (optional for tests/tooling)
```

---

## Modular Architecture

### 1. Ingest & Synchronisation
- Frame capture module (HDMI→USB) plus cursor tracking.
- Low frequency capture (1–2 fps) to conserve resources on Jetson.
- Outputs keyframes with cursor coordinates.

### 2. Perception Agents
- Lightweight detector for UI elements.
- OCR for text recognition in regions of interest.
- Scene graph builder (`SceneGraph`) to create a structured representation of the interface.

### 3. Understanding Agent (LLM)
- Local LLM (Mistral / Llama 3.x 7–8B quantised for Jetson).
- Input: serialised `SceneGraph`.
- Output: structured step-by-step plans with function-calling.

### 4. Planner Agent
- Converts high-level goals into atomic actions.
- Enforces **safety policies** (whitelists, human confirmations).
- Handles monitoring, error detection, and re-planning.

### 5. Executor Agent (HID)
- Executes physical actions on the external computer (mouse and keyboard).
- Exposed via REST API controlling a Bluetooth HID GATT server or USB gadget HID.

### 6. Memory & Tools
- Short- and long-term context memory (FAISS/Chroma DB).
- Integration with fallback tools (system scripts, APIs).

### 7. Supervision & UI
- Local web dashboard (FastAPI + Vue/React) for monitoring, human confirmations, and activity logs.

---

## Containerisation & Deployment

### Services (dedicated Docker containers)
- **gateway**: REST API + UI proxy.
- **perception**: detection + OCR.
- **llm**: local model (OpenAI-compatible API).
- **planner**: orchestration.
- **hid**: execution layer (Bluetooth HID/USB gadget).
- **memory**: retrieval-augmented generation store.
- **bus**: optional messaging backbone (Redis/NATS).

### Compose with profiles
`docker-compose.profiles.yml` defines selective start-up for:
- `core`
- `perception`
- `llm`
- `hid`
- `bus`

### HID Requirements
- **Bluetooth**: `network_mode: host`, `privileged: true`, BlueZ access.
- **USB gadget**: Jetson kernel support required, run with `--privileged`.

---

## Security & Governance
- **Assistive mode** ensures user control is never pre-empted.
- Critical actions require explicit confirmation.
- Centralised logging enables auditing and replay.

---

## MVP Delivery Checklist
- [ ] HDMI→USB capture at 1 fps exposed via `/perception/capture`
- [ ] Basic HID API endpoints: `/hid/click`, `/hid/text`
- [ ] Local quantised LLM (Q4-K) converting scene→actions
- [ ] Planner with minimal safety policy
- [ ] Web UI with logging and confirmation mechanisms

---

## Roadmap
1. **MVP (2 weeks)**: capture → perception → planner → HID execution → web UI
2. **Iteration 2**: add memory and tools, JSON logging, Prometheus metrics
3. **Iteration 3**: introduce event bus, scale perception/planner modules
4. **Iteration 4**: add on-screen overlay output to external host (OSD)

---

## Getting Started

1. Copy `.env.example` to `.env` and adjust paths/devices.
2. Build containers with `make build` or `docker compose build`.
3. Launch the stack with `make up` (default `core` profile) and visit the gateway dashboard.
4. Run the smoke tests with `make test`.

For development tips, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and the service-level READMEs.
