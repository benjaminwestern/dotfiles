#!/usr/bin/env python3
"""Reapply local-only launch settings after native Engram setup."""
from pathlib import Path
import json
import re
import tomllib

home_dir = Path.home()
engram_mcp = [
    "mise",
    "exec",
    "github:Gentleman-Programming/engram@2.0.0-rc.10",
    "--",
    "engram",
    "mcp",
    "--tools=agent",
]
config = home_dir / ".codex/config.toml"
text = config.read_text()
data = tomllib.loads(text)
assert "engram" in data.get("mcp_servers", {}), "Run engram setup codex first"


def update_engram_section(match):
    section = match.group(0)
    section = re.sub(r'^command\s*=.*$', 'command = "mise"', section, flags=re.M)
    args = "args = " + json.dumps(engram_mcp[1:])
    if re.search(r'^args\s*=', section, flags=re.M):
        section = re.sub(r'^args\s*=.*$', args, section, flags=re.M)
    else:
        section = re.sub(r'^(command\s*=.*)$', r'\1\n' + args, section, count=1, flags=re.M)
    return section


text = re.sub(r'^\[mcp_servers\.engram\]\n(?:(?!^\[).)*', update_engram_section, text, flags=re.M | re.S)
if data.get("plugins", {}).get("engram@engram") is not None:
    text = re.sub(r'(^\[plugins\."engram@engram"\]\n)(enabled\s*=\s*)true', r'\1\2false', text, flags=re.M)
assert tomllib.loads(text)["mcp_servers"]["engram"]["command"] == "mise"
assert tomllib.loads(text)["mcp_servers"]["engram"]["args"] == engram_mcp[1:]
assert not tomllib.loads(text).get("plugins", {}).get("engram@engram", {}).get("enabled", False)
config.write_text(text)
config.chmod(0o600)

opencode = home_dir / ".config/opencode/opencode.json"
data = json.loads(opencode.read_text())
data["mcp"]["engram"]["command"] = engram_mcp
opencode.write_text(json.dumps(data, indent=2) + "\n")

print("Applied the local launcher to Codex and OpenCode and disabled optional Codex hooks.")
