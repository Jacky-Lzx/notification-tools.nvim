#!/usr/bin/env python3
"""Check public LuaLS contracts with valid and intentionally invalid consumers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    for binary in ("nvim", "lua-language-server"):
        if not shutil.which(binary):
            raise SystemExit(f"{binary} is required for the optional type checks")
    with tempfile.TemporaryDirectory(prefix="notification-types-") as temp:
        temporary = Path(temp)
        env = dict(os.environ, XDG_STATE_HOME=temp + "/state", XDG_CACHE_HOME=temp + "/cache", XDG_DATA_HOME=temp + "/data", NVIM_LOG_FILE=temp + "/nvim.log")
        runtime = subprocess.run(["nvim", "--headless", "-n", "-u", "NONE", "-i", "NONE", "--noplugin", "+lua io.stdout:write(vim.env.VIMRUNTIME)", "+qa"], env=env, capture_output=True, text=True, check=True).stdout
        config = {
            "runtime.version": "LuaJIT",
            "runtime.path": ["?.lua", "?/init.lua"],
            "workspace.library": [str(ROOT / "lua"), str(Path(runtime) / "lua")],
            "workspace.checkThirdParty": False,
            "diagnostics.libraryFiles": "Disable",
            "diagnostics.globals": ["vim"],
        }
        settings = temporary / "config.json"
        settings.write_text(json.dumps(config))
        for name, fixture in (("valid", "valid.lua"), ("invalid", "invalid.lua.txt")):
            workspace = temporary / name
            workspace.mkdir()
            source = (ROOT / "tests/types" / fixture).read_text()
            (workspace / "consumer.lua").write_text(source)
            report = temporary / (name + "-report.json")
            command = ["lua-language-server", "--check=" + str(workspace), "--configpath=" + str(settings), "--logpath=" + str(temporary / (name + "-logs")), "--check_format=json", "--check_out_path=" + str(report), "--checklevel=Warning"]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            allowed_codes = (0,) if name == "valid" else (0, 1)
            if result.returncode not in allowed_codes or not report.exists():
                raise SystemExit(result.stdout + result.stderr)
            data = json.loads(report.read_text())
            diagnostics = [item for items in data.values() for item in items] if isinstance(data, dict) else data
            if name == "valid":
                assert not diagnostics, json.dumps(diagnostics, indent=2)
            else:
                expected = {index for index, line in enumerate(source.splitlines()) if "expect-type-error" in line}
                found = {item["range"]["start"]["line"] for item in diagnostics if item["code"] in {"assign-type-mismatch", "param-type-mismatch"}}
                assert found == expected, json.dumps(diagnostics, indent=2)
            print(f"types: {name} consumer contract passed")


if __name__ == "__main__":
    main()
