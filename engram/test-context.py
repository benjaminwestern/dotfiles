#!/usr/bin/env python3
"""Verify private organisation routing without touching the Engram store."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
RESOLVER = HERE / "engram-context.py"


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        env={**os.environ, **(env or {})},
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def resolve(directory: Path, registry: Path) -> dict[str, str]:
    output = run(
        sys.executable,
        str(RESOLVER),
        str(directory),
        env={"ENGRAM_ORGANISATIONS_FILE": str(registry)},
    )
    return dict(line.split("=", 1) for line in output.splitlines())


with tempfile.TemporaryDirectory(prefix="engram-context-") as temporary:
    root = Path(temporary)
    workspace = root / "workspace"
    repository = workspace / "repository"
    linked = root / "linked"
    outside = root / "outside"
    repository.mkdir(parents=True)
    outside.mkdir()

    run("git", "init", "-q", str(repository))
    run(
        "git",
        "-C",
        str(repository),
        "-c",
        "user.name=Engram test",
        "-c",
        "user.email=engram-test@localhost",
        "commit",
        "--allow-empty",
        "-qm",
        "fixture",
    )

    registry = root / "organisations.tsv"
    registry.write_text(f"example\torg-example\t{workspace}\n", encoding="utf-8")
    registry.chmod(0o600)

    direct = resolve(repository, registry)
    assert direct["org_project"] == "org-example"
    assert direct["domain_source"] == "cwd"

    run("git", "-C", str(repository), "worktree", "add", "--detach", str(linked))
    inherited = resolve(linked, registry)
    assert inherited["org_project"] == "org-example"
    assert inherited["domain_source"] == "git_common_dir"
    assert Path(inherited["repo_root"]) == linked.resolve()

    unrelated = resolve(outside, registry)
    assert unrelated["org_project"] == ""
    assert unrelated["domain_source"] == "none"

print("PASS portable Engram context routing")
