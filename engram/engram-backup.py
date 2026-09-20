#!/usr/bin/env python3
"""Export the complete local Engram store to a private backup file."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
import os
import subprocess
import uuid


VERSION = "2.0.0-rc.10"


def main() -> None:
    backup_dir = Path.home() / ".engram" / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    destination = backup_dir / f"engram-{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}.json"
    temporary = destination.with_suffix(".tmp")
    environment = {
        **os.environ,
        "ENGRAM_DATA_DIR": str(Path.home() / ".engram"),
        "ENGRAM_CLOUD_AUTOSYNC": "0",
        "ENGRAM_NO_UPDATE_CHECK": "1",
    }
    try:
        subprocess.run(
            [
                "mise",
                "exec",
                f"github:Gentleman-Programming/engram@{VERSION}",
                "--",
                "engram",
                "export",
                str(temporary),
                "--all",
            ],
            env=environment,
            check=True,
        )
        temporary.replace(destination)
        destination.chmod(0o600)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Backup: {destination}")


if __name__ == "__main__":
    main()
