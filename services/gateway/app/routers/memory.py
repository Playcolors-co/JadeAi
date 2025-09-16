"""Memory API router."""

from __future__ import annotations

from datetime import datetime
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()


class MemoryRecord(BaseModel):
    id: str
    timestamp: datetime
    content: str


_MEMORY: list[MemoryRecord] = []


@router.get("/recent", response_model=list[MemoryRecord])
async def recent(limit: int = 10) -> list[MemoryRecord]:
    return _MEMORY[-limit:]


@router.post("/append", response_model=MemoryRecord)
async def append(record: MemoryRecord) -> MemoryRecord:
    _MEMORY.append(record)
    return record
