#!/usr/bin/env python3
"""Resolve a repository's private organisation workspace, if configured."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def git(directory: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(directory), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def registry_rows(path: Path):
    if not path.is_file():
        return
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3 or not all(fields):
            raise ValueError(f"Invalid organisation registry row {number} in {path}")
        name, project, root = fields
        yield name, project, Path(root).expanduser().resolve()


def contains(root: Path, candidate: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def classify(candidate: Path, registry: Path):
    for name, project, root in registry_rows(registry) or ():
        if root.is_dir() and contains(root, candidate):
            return name, project, root
    return "", "", None


def main() -> int:
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else Path.cwd()).expanduser().resolve()
    registry = Path(
        os.environ.get("ENGRAM_ORGANISATIONS_FILE", "~/.engram/organisations.tsv")
    ).expanduser()
    repository = git(directory, "rev-parse", "--show-toplevel")
    organisation, project, workspace = classify(directory, registry)
    source = "cwd" if organisation else "none"

    if repository:
        common = git(directory, "rev-parse", "--path-format=absolute", "--git-common-dir")
        if common:
            common_path = Path(common).resolve()
            common_org, common_project, common_workspace = classify(common_path, registry)
            if common_org:
                if organisation and common_org != organisation:
                    print(
                        "Conflicting directory and Git worktree organisations. "
                        "Do not recall or save organisation memory.",
                        file=sys.stderr,
                    )
                    return 2
                if not organisation:
                    organisation, project, workspace = common_org, common_project, common_workspace
                    source = "git_common_dir"

    print(f"cwd={directory}")
    print(f"org={organisation}")
    print(f"org_project={project}")
    print(f"workspace_root={workspace or ''}")
    print(f"repo_root={repository}")
    print(f"domain_source={source}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(2)
