#!/usr/bin/env python3
"""Verify delayed progress and compact results on Neovim's actual UI grid."""
import importlib.util
import os
from pathlib import Path
import signal
import tempfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("capture", ROOT / "scripts/screenshots.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def run(env):
    ui = capture.Capture(env)

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def flush(now=None):
        prefix = f"now = {now}; " if now is not None else ""
        lua(prefix + "vim.api.nvim_exec_autocmds('VimResized', {}); vim.wait(90); vim.cmd.redraw()")

    def screen():
        return "\n".join("".join(cell[0] for cell in row) for row in ui.grid)

    def panel():
        return lua("local f = h.floats(); return #f > 0 and f[1] or nil")

    try:
        ui.request("nvim_ui_attach", [100, 32, {"rgb": True, "ext_linegrid": True}])
        lua("""
            h = dofile('tests/helpers.lua')
            model = require('notification-tools.state')
            real_clock = model.now
            now = 1000
            model.now = function() return now end
            tools = require('notification-tools')
            tools.setup({notify = false, progress = {history = 'all', stale_timeout = 0}})
            fast = tools.progress({title = '', source = 'basedpyright'})
            now = 1050
            fast:finish()
        """)
        flush(2000)
        assert panel() is None, screen()
        assert not lua("return package.loaded['notification-tools.view'] ~= nil")
        assert lua("return #tools.tasks() == 1 and #tools.history() == 1")

        # Presentation starts at the deadline, preserving names across blank reports.
        lua("""
            tools.setup({notify = false, progress = {history = 'all', stale_timeout = 0}})
            a = tools.progress({title = 'Index workspace', source = 'basedpyright', percentage = 25})
            b = tools.progress({title = '', source = 'basedpyright', message = 'Checking files'})
            a:update({title = '  '})
            original_win = vim.api.nvim_get_current_win()
            original_buf = vim.api.nvim_get_current_buf()
        """)
        flush(2179)
        assert panel() is None, screen()
        flush(2180)
        first = panel()
        assert first is not None, screen()
        assert "Index workspace" in screen() and "25%" in screen(), screen()
        assert "Checking files" in screen() and "0.0s" not in screen(), screen()
        assert lua("return tools.tasks()[2].title") == "Index workspace"
        assert "━" in screen(), screen()

        flush(4000)
        lua("a:finish()")
        flush()
        assert "Index workspace" in screen() and "2.0s" in screen(), screen()
        assert "Completed" not in screen() and "100%" not in screen(), screen()
        assert "━" not in screen(), screen()
        assert panel()["win"] == first["win"] and panel()["buf"] == first["buf"]

        # Equivalent unnamed successes collapse, then expire independently.
        lua("""
            c = tools.progress({title = '', source = 'basedpyright'})
            d = tools.progress({title = '', source = 'basedpyright'})
            now = 4200; c:finish()
            now = 4300; d:finish()
        """)
        flush()
        assert "Completed ×2" in screen(), screen()
        assert lua("return #tools.history()") == 3
        lua("""
            now = 4400
            tools.progress({title = 'Compile', source = 'build'}):finish('Missing file', 'error')
        """)
        flush()
        assert "Compile" in screen() and "Missing file" in screen(), screen()
        assert lua("return tools.tasks()[1].lifetime") == 5000
        flush(5750)
        assert "Completed ×2" not in screen() and "Completed" in screen(), screen()
        flush(5801)
        assert "Completed" not in screen() and "Missing file" in screen(), screen()
        assert lua("return #tools.history()") == 4

        # Updates and layout changes must preserve editing, focus and cursor.
        ui.request("nvim_input", ["i"])
        for index, char in enumerate("typing"):
            lua("b:update({title = '', message = 'Checking files'})")
            ui.request("nvim_input", [char])
            flush(5900 + index * 90)
            assert lua("return vim.api.nvim_get_mode().mode:sub(1, 1)") == "i"
            assert lua("return vim.api.nvim_get_current_win() == original_win")
            assert lua("return vim.api.nvim_get_current_buf() == original_buf")
        assert lua("return vim.api.nvim_get_current_line()") == "typing"
        assert lua("return vim.api.nvim_win_get_cursor(0)") == [1, 6]
        ui.request("nvim_input", ["<Esc>"])
        flush(9401)
        assert "Missing file" not in screen() and "Checking files" in screen(), screen()
        assert panel()["win"] == first["win"] and panel()["buf"] == first["buf"]
        lua("tools.teardown()")

        # With a real clock, a quiet producer needs no update to become visible.
        lua("model.now = real_clock; "
            "tools.setup({notify = false, progress = {stale_timeout = 0}}); "
            "tools.progress({title = 'Quiet task', percentage = 40}); "
            "vim.wait(280); vim.cmd.redraw()")
        assert "Quiet task" in screen(), screen()
        lua("tools.teardown()")
        print("progress UI: delayed startup, blank titles, compact completion, grouping/expiry, "
              "failure retention, editing/focus and quiet-task deadlines passed")
    finally:
        ui.close()


def main():
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Progress UI test timed out")))
    signal.alarm(25)
    try:
        with tempfile.TemporaryDirectory(prefix="notification-progress-ui-") as temp:
            run(dict(os.environ, XDG_STATE_HOME=temp + "/state", XDG_CACHE_HOME=temp + "/cache",
                     XDG_DATA_HOME=temp + "/data", NVIM_LOG_FILE=temp + "/nvim.log"))
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main()
