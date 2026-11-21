import os
from dataclasses import dataclass, field
from pathlib import Path

from app.audio.choir import DEFAULT_IR_DIR


@dataclass
class Settings:
    max_upload_bytes: int = int(float(os.getenv("CHOIR_MAX_UPLOAD_MB", "25")) * 1024 * 1024)
    min_seconds: float = float(os.getenv("CHOIR_MIN_SECONDS", "0.5"))
    max_seconds: float = float(os.getenv("CHOIR_MAX_SECONDS", "120"))
    ir_dir: Path = field(default_factory=lambda: Path(os.getenv("CHOIR_IR_DIR", str(DEFAULT_IR_DIR))))


settings = Settings()
