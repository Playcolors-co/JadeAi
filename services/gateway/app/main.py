"""FastAPI entry point for the JadeAI gateway."""

from __future__ import annotations

from fastapi import FastAPI

from .deps import get_settings
from .routers import actions, health, hid, memory, perception, planner

app = FastAPI(title="JadeAI Gateway", version="2.0.0")


@app.on_event("startup")
async def startup_event() -> None:
    settings = get_settings()
    app.state.settings = settings


app.include_router(health.router)
app.include_router(perception.router, prefix="/perception", tags=["perception"])
app.include_router(planner.router, prefix="/planner", tags=["planner"])
app.include_router(actions.router, prefix="/actions", tags=["actions"])
app.include_router(hid.router, prefix="/hid", tags=["hid"])
app.include_router(memory.router, prefix="/memory", tags=["memory"])


@app.get("/")
async def root() -> dict[str, str]:
    settings = get_settings()
    return {"service": app.title, "environment": settings.environment}
