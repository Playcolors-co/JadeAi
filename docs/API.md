# API Overview

The Gateway service exposes a REST/WS API. Selected endpoints:

| Method | Path | Description |
| ------ | ---- | ----------- |
| GET    | `/health` | Service heartbeat |
| POST   | `/perception/analyse` | Submit a captured frame for analysis |
| GET    | `/planner/plan/{plan_id}` | Fetch the current plan |
| POST   | `/planner/plan` | Request a new plan |
| POST   | `/actions/execute` | Execute a validated action |
| POST   | `/hid/click` | Trigger a click |
| POST   | `/hid/text` | Type a string |

WebSocket channel `/ws/events` broadcasts memory and bus events.

Each service also exposes lightweight APIs for debugging (see `services/*`). The tests demonstrate sample payloads.
