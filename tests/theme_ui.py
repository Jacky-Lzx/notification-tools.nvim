#!/usr/bin/env python3
"""Verify visible RGB cells across theme switches, Markdown and task fades.

Uses standalone no-clear themes by default. Set NOTIFICATION_TOOLS_THEME_TOOLS_ROOT
and NOTIFICATION_TOOLS_THEME_ROOT to also exercise managed Dracula/Latte switching
with existing theme-tools and Catppuccin checkouts; never installs dependencies.
"""
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

    def flush():
        lua("vim.wait(80); vim.cmd.redraw()")

    def word_color(word, expected, field="foreground"):
        matches = 0
        for row in ui.grid:
            text = "".join(cell[0] for cell in row)
            start = text.find(word)
            if start < 0:
                continue
            matches += 1
            for _, attr in row[start:start + len(word)]:
                fallback = ui.fg if field == "foreground" else ui.bg
                actual = ui.attrs.get(attr, {}).get(field, fallback)
                assert actual == expected, (word, field, hex(expected), hex(actual))
        assert matches, f"Missing visible text: {word}"

    try:
        ui.request("nvim_ui_attach", [120, 45, {"rgb": True, "ext_linegrid": True}])
        managed = lua(r"""
            vim.opt.rtp:prepend(vim.fn.getcwd())
            vim.o.termguicolors = true
            vim.o.laststatus = 0
            local root, cat = vim.env.NOTIFICATION_TOOLS_THEME_TOOLS_ROOT, vim.env.NOTIFICATION_TOOLS_THEME_ROOT
            if root and root ~= '' then
              assert(cat and cat ~= '', 'Catppuccin checkout is required for managed themes')
              vim.opt.rtp:prepend(root)
              vim.opt.rtp:prepend(cat)
              require('catppuccin').setup({ compile_path = vim.env.XDG_CACHE_HOME .. '/catppuccin' })
              themes = require('theme_tools')
              themes.setup({ persist = false, discover = false, catppuccin = false, dracula = false,
                default = 'theme-tools-dracula', themes = {
                  { name = 'theme-tools-dracula', transparent = false },
                  { name = 'catppuccin-latte', transparent = false },
                } })
            end
            function apply_theme(light)
              if themes then
                assert(themes.set(light and 'catppuccin-latte' or 'theme-tools-dracula'))
              else
                -- Reproduce a scheme that does not clear existing plugin groups.
                vim.g.colors_name = nil
                vim.o.background = light and 'light' or 'dark'
                vim.api.nvim_set_hl(0, 'Normal', {fg = light and 0x4c4f69 or 0xf8f8f2,
                  bg = light and 0xeff1f5 or 0x282a36})
                vim.api.nvim_set_hl(0, 'NormalFloat', {fg = light and 0x4c4f69 or 0xf8f8f2,
                  bg = light and 0xe6e9ef or 0x21222c})
                vim.api.nvim_set_hl(0, 'Comment', {fg = light and 0x7c7f93 or 0x6272a4})
                vim.api.nvim_exec_autocmds('ColorScheme', {pattern = 'no-clear'})
              end
            end
            apply_theme(false)
            model = require('notification-tools.state')
            clock = model.now
            now = 1000
            model.now = function() return now end
            tools = require('notification-tools')
            tools.setup({ notify = false, timeout = 0,
              progress = { stale_timeout = 0, done_ttl = 1000, fade_out = 200 } })
            tools.notify('NoticeWord **BoldWord**', 'warn', {title = 'NoticeTitle', details = 'DetailWord'})
            done = tools.progress({title = 'TaskWord', percentage = 50, message = 'TaskDetail'})
            tools.progress({title = 'ActiveWord', percentage = 20})
            return themes ~= nil
        """)
        for light in (False, True, False):
            lua(f"apply_theme({'true' if light else 'false'})")
            flush()
            colors = lua("return { fg = vim.api.nvim_get_hl(0, {name='NormalFloat', link=false}).fg, "
                         "bg = vim.api.nvim_get_hl(0, {name='NormalFloat', link=false}).bg }")
            for word in ("NoticeWord", "BoldWord", "TaskWord", "ActiveWord"):
                word_color(word, colors["fg"])
                word_color(word, colors["bg"], "background")

        if managed:
            # Preview cancellation restores a full highlight snapshot. A later
            # switch must still recognize and update the plugin's own defaults.
            lua("snapshot = require('theme_tools.colors').snapshot(); apply_theme(true)")
            flush()
            lua("require('theme_tools.colors').restore(snapshot)")
            flush()

        lua("apply_theme(true); tools.show_history()")
        flush()
        fg = lua("return vim.api.nvim_get_hl(0, {name='NormalFloat', link=false}).fg")
        word_color("BoldWord", fg)
        lua("apply_theme(false)")
        flush()
        fg = lua("return vim.api.nvim_get_hl(0, {name='NormalFloat', link=false}).fg")
        word_color("BoldWord", fg)
        ui.request("nvim_input", ["q"])
        flush()

        lua("done:finish(); now = 1900; vim.api.nvim_exec_autocmds('VimResized', {})")
        flush()
        for light in (True, False):
            lua(f"apply_theme({'true' if light else 'false'})")
            flush()
            fg, bg = lua("local h=vim.api.nvim_get_hl(0, {name='NotificationToolsProgressNormal', link=false}); return {h.fg, h.bg}")
            # Lua's color mixer rounds halves up, rather than Python's ties-to-even.
            faded = sum(int((((bg >> shift) & 255) + ((fg >> shift) & 255)) / 2 + 0.5) << shift
                        for shift in (16, 8, 0))
            word_color("TaskWord", faded)
            word_color("ActiveWord", fg)
            word_color("BoldWord", fg)

        if managed:
            lua("vim.api.nvim_set_hl(0, 'NormalFloat', {fg=0x314159, bg=0x21222c}); themes.refresh_palette()")
            flush()
            word_color("NoticeWord", 0x314159)
            word_color("BoldWord", 0x314159)
            word_color("ActiveWord", 0x314159)
        lua("tools.teardown(); model.now = clock")
        print("theme RGB UI: " + ("managed Dracula/Latte" if managed else "standalone no-clear themes")
              + ", dark/light/dark, open history, Markdown and independent task fades"
              + (", snapshot restoration and palette refresh" if managed else "") + " passed")
    finally:
        ui.close()


def main():
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Theme UI test timed out")))
    signal.alarm(25)
    try:
        with tempfile.TemporaryDirectory(prefix="notification-theme-ui-") as temp:
            env = dict(os.environ, XDG_STATE_HOME=temp + "/state", XDG_CACHE_HOME=temp + "/cache",
                       XDG_DATA_HOME=temp + "/data", NVIM_LOG_FILE=temp + "/nvim.log")
            run(env)
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main()
