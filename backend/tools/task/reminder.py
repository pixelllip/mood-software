from __future__ import annotations
import os
from pathlib import Path
from datetime import datetime

def schedules_dir() -> Path:
    base_path = os.getenv("BASE_PATH", ".")
    root_dir = Path(base_path)
    out_dir = root_dir / "Schedules"
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir

def stable_schedule_path(date_str: str | None = None) -> Path:
    safe_date = (date_str or "").strip() or datetime.now().strftime("%Y-%m-%d")
    return schedules_dir() / f"schedule_{safe_date}.txt"

def read_schedule_text(date_str: str | None = None) -> str:
    path = stable_schedule_path(date_str)
    if not path.exists():
        return ""
    try:
        return path.read_text(encoding="utf-8").strip()
    except Exception:
        return ""

def open_schedule_file(date_str: str | None = None) -> None:
    path = stable_schedule_path(date_str)
    if path.exists():
        os.startfile(str(path))
