#!/usr/bin/env python3
"""Apply local-only Engram launch settings to active client configs."""
from pathlib import Path
import json
import os
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


def remove_top_level_settings(text, names):
    result = []
    in_table = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            in_table = True
        if not in_table and any(re.match(rf"^{re.escape(name)}\s*=", stripped) for name in names):
            continue
        result.append(line)
    return "\n".join(result)


def update_engram_section(match):
    section = match.group(0)
    section = re.sub(r'^command\s*=.*$', 'command = "mise"', section, flags=re.M)
    args = "args = " + json.dumps(engram_mcp[1:])
    if re.search(r'^args\s*=', section, flags=re.M):
        section = re.sub(r'^args\s*=.*$', args, section, flags=re.M)
    else:
        section = re.sub(r'^(command\s*=.*)$', r'\1\n' + args, section, count=1, flags=re.M)
    return section


def disable_engram_plugin(match):
    section = match.group(0)
    if re.search(r"^enabled\s*=", section, flags=re.M):
        return re.sub(r"^enabled\s*=.*$", "enabled = false", section, flags=re.M)
    return re.sub(r"^(\[plugins\.\"engram@engram\"\])$", r"\1\nenabled = false", section, count=1, flags=re.M)


codex_home_setting = os.environ.get("CODEX_HOME")
codex_home = Path(codex_home_setting).expanduser() if codex_home_setting else home_dir / ".codex"
config = codex_home / "config.toml"
text = config.read_text(encoding="utf-8") if config.exists() else ""
text = remove_top_level_settings(
    text,
    {"model_instructions_file", "experimental_compact_prompt_file"},
)

engram_pattern = r"^\[mcp_servers\.engram\]\n(?:(?!^\[).)*"
if re.search(engram_pattern, text, flags=re.M | re.S):
    text = re.sub(engram_pattern, update_engram_section, text, flags=re.M | re.S)
else:
    text = text.rstrip()
    if text:
        text += "\n\n"
    text += "[mcp_servers.engram]\n"
    text += 'command = "mise"\n'
    text += "args = " + json.dumps(engram_mcp[1:]) + "\n"

plugin_pattern = r'^\[plugins\."engram@engram"\]\n(?:(?!^\[).)*'
if re.search(plugin_pattern, text, flags=re.M | re.S):
    text = re.sub(plugin_pattern, disable_engram_plugin, text, flags=re.M | re.S)

parsed = tomllib.loads(text)
if parsed["mcp_servers"]["engram"]["command"] != "mise":
    raise RuntimeError("Failed to configure the Codex Engram launcher")
if parsed["mcp_servers"]["engram"]["args"] != engram_mcp[1:]:
    raise RuntimeError("Failed to configure the Codex Engram arguments")
if parsed.get("plugins", {}).get("engram@engram", {}).get("enabled", False):
    raise RuntimeError("Failed to disable the optional Codex Engram plugin")
if "model_instructions_file" in parsed or "experimental_compact_prompt_file" in parsed:
    raise RuntimeError("Failed to remove Codex prompt overrides")

config.parent.mkdir(parents=True, exist_ok=True)
config.write_text(text.rstrip() + "\n", encoding="utf-8")
config.chmod(0o600)

xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
config_home = Path(xdg_config_home).expanduser() if xdg_config_home else home_dir / ".config"
opencode = config_home / "opencode/opencode.json"
data = json.loads(opencode.read_text(encoding="utf-8"))
mcp = data["mcp"]
mcp["servers"]["engram"]["command"] = engram_mcp
mcp.pop("engram", None)
opencode.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

print("Applied local Engram launchers and restored Codex prompt defaults.")
