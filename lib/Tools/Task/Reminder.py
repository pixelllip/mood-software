from __future__ import annotations

import os
from pathlib import Path
from datetime import datetime


def schedules_dir() -> Path:
    """
    返回 Schedules 目录路径（与 ui.py 的保存逻辑兼容）。
    - 优先 BASE_PATH/Schedules/
    - 否则为当前文件所在目录下的 Schedules/
    """
    base_path = os.getenv("BASE_PATH")
    root_dir = Path(base_path) if base_path else Path(__file__).resolve().parent
    out_dir = root_dir / "Schedules"
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir


def stable_schedule_path(date_str: str | None = None) -> Path:
    """固定命名：schedule_YYYY-MM-DD.txt"""
    safe_date = (date_str or "").strip() or datetime.now().strftime("%Y-%m-%d")
    return schedules_dir() / f"schedule_{safe_date}.txt"


def read_schedule_text(date_str: str | None = None) -> str:
    path = stable_schedule_path(date_str)
    if not path.exists():
        return ""
    try:
        return path.read_text(encoding="utf-8").strip()
    except Exception:
        try:
            return path.read_text(encoding="gbk").strip()
        except Exception:
            return ""


def open_schedule_file(date_str: str | None = None) -> None:
    """Windows 下打开当日日程文件（如果存在）。"""
    path = stable_schedule_path(date_str)
    if path.exists():
        os.startfile(str(path))  # type: ignore[attr-defined]
