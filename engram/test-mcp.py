#!/usr/bin/env python3
"""Start each configured Engram MCP transport and perform read-only checks."""

from __future__ import annotations

import json
import os
from pathlib import Path
from queue import Queue
import subprocess
import threading
import tomllib


HOME = Path.home()
ROOT = Path(__file__).resolve().parent.parent


def command_for(client: str) -> tuple[list[str], dict[str, str]]:
    if client == "codex":
        config = tomllib.loads((HOME / ".codex/config.toml").read_text(encoding="utf-8"))
        entry = config["mcp_servers"]["engram"]
        command = [entry["command"], *entry.get("args", [])]
    else:
        config = json.loads((HOME / ".config/opencode/opencode.json").read_text(encoding="utf-8"))
        entry = config["mcp"]["engram"]
        raw = entry["command"]
        command = raw if isinstance(raw, list) else [raw, *entry.get("args", [])]
    command = [part.replace("{env:HOME}", str(HOME)) for part in command]
    environment = entry.get("environment", entry.get("env", {}))
    return command, {str(key): str(value) for key, value in environment.items()}


class MCP:
    def __init__(self, client: str):
        command, environment = command_for(client)
        self.process = subprocess.Popen(
            command,
            cwd=ROOT,
            env={**os.environ, **environment},
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        self.responses: Queue[str] = Queue()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.number = 0
        self.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": f"engram-{client}-check", "version": "1"},
            },
        )
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.responses.put(line)

    def send(self, message: dict) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def request(self, method: str, params: dict) -> dict:
        self.number += 1
        self.send({"jsonrpc": "2.0", "id": self.number, "method": method, "params": params})
        while True:
            response = json.loads(self.responses.get(timeout=20))
            if response.get("id") != self.number:
                continue
            if "error" in response:
                raise AssertionError(response["error"])
            return response["result"]

    def close(self) -> None:
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


projects: dict[str, str] = {}
for name in ("codex", "opencode"):
    client = MCP(name)
    try:
        tools = client.request("tools/list", {})["tools"]
        tool_names = {tool["name"] for tool in tools}
        assert {"mem_current_project", "mem_search", "mem_save"} <= tool_names
        result = client.request(
            "tools/call",
            {"name": "mem_current_project", "arguments": {}},
        )
        content = "\n".join(item["text"] for item in result["content"] if item["type"] == "text")
        projects[name] = json.loads(content)["project"]
    finally:
        client.close()

assert projects["codex"] == projects["opencode"] == "dotfiles", projects
print("PASS Codex and OpenCode Engram MCP connectivity")
