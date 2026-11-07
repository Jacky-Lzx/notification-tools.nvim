#!/usr/bin/env python3
"""Exercise native fallback and a separate cmdline renderer with a real RPC UI."""
import importlib.util
import os
from pathlib import Path
import signal

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("capture", ROOT / "scripts/screenshots.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def main():
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("UI test timed out")))
    signal.alarm(25)
    ui = capture.Capture(os.environ.copy())

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def keys(value):
        ui.request("nvim_input", [value])
        lua("vim.wait(40)")

    def screen():
        return "\n".join("".join(cell[0] for cell in row) for row in ui.grid)

    def word_color(word, expected):
        matches = 0
        for row in ui.grid:
            text = "".join(cell[0] for cell in row)
            start = text.find(word)
            if start >= 0:
                matches += 1
                for _, attr in row[start:start + len(word)]:
                    assert ui.attrs.get(attr, {}).get("foreground", ui.fg) == expected, (word, expected)
        assert matches, f"Missing visible text: {word}"

    try:
        ui.request("nvim_ui_attach", [100, 32, {"rgb": True, "ext_linegrid": True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); tools = require('notification-tools'); "
            "tools.setup({ timeout = 0, messages = { enabled = true } })")
        assert lua("return vim.o.cmdheight") == 1
        assert not lua("return package.loaded['notification-tools.messages'] ~= nil")
        keys(":echomsg")
        assert ":echomsg" in screen().splitlines()[-1], screen()
        keys(" 'native-before'<CR>")
        assert "native-before" in screen(), screen()
        assert lua("return #tools.history()") == 0

        lua("provider = dofile('tests/fixtures/cmdline.lua'); lease = assert(tools.attach_messages())")
        keys(":echo '**captured**'<CR>")
        records = lua("return tools.history()")
        assert any(r["message"] == "**captured**" and not r["markdown"] for r in records), records
        assert "**captured**" in screen(), screen()
        assert lua("return vim.tbl_contains(provider.events, 'cmdline_show')")
        assert lua("return vim.tbl_contains(provider.events, 'cmdline_hide')")
        lua("vim.api.nvim_set_hl(0,'WarningMsg',{fg=0xffaa11}); "
            "vim.api.nvim_echo({{'NativeWord','WarningMsg'},{' plain'}},true,{});vim.wait(60);vim.cmd.redraw()")
        # Semantic group IDs were added to native chunks in Neovim 0.12.
        if lua("return vim.fn.has('nvim-0.12') == 1"):
            word_color("NativeWord", 0xffaa11)
            lua("vim.api.nvim_set_hl(0,'WarningMsg',{fg=0x11aaee}); "
                "vim.api.nvim_exec_autocmds('ColorScheme',{});vim.wait(60);vim.cmd.redraw()")
            word_color("NativeWord", 0x11aaee)
        lua("""
            vim.api.nvim_set_hl(0,'Boolean',{fg=0xcc55aa})
            local text = 'Literal **keep**\\n{ flag = true }'
            tools.notify(text, 'info', {markdown=false, spans={{start=17,finish=#text,filetype='lua'}}})
            vim.wait(60);vim.cmd.redraw()
        """)
        assert "Literal **keep**" in screen()
        word_color("true", 0xcc55aa)
        keys(":echo")
        assert ":echo" in screen(), screen()
        keys("<Esc>")

        # Real undo/redo feedback must not create popups or captured history.
        lua("tools.dismiss(); vim.cmd.enew()")
        keys("iundo-redo-check<Esc>")
        before_undo = lua("return #tools.history()")
        semantic_undo = lua("return vim.fn.has('nvim-0.11') == 1")
        for command, expected in [("u", ""), ("<C-r>", "undo-redo-check")]:
            keys(command)
            assert lua("return vim.api.nvim_get_current_line()") == expected
            if semantic_undo:
                assert lua("return #tools.history()") == before_undo
            else:
                # 0.10 sends an empty kind for undo/redo; preserve that message
                # instead of guessing from localized text and hiding real echoes.
                assert lua("return tools.history()[#tools.history()].title") == "Neovim"
            assert "Neovim: undo" not in screen() and "Neovim: redo" not in screen(), screen()
        lua("vim.bo.modified = false")

        # The provider, rather than notifications, owns nested input and confirms.
        keys(":lua vim.g.input_result = vim.fn.input('lease-input: ')<CR>")
        assert "lease-input:" in screen(), screen()
        keys("answer<CR>")
        assert lua("return vim.g.input_result") == "answer"
        # Older Neovim blocks ordinary RPC execution and discards typeahead
        # while confirm() waits. Answer only after the provider sees the prompt.
        ui.request("nvim_input", [":lua vim.g.confirm_result = vim.fn.confirm('lease-confirm', '&Yes\\n&No', 2)<CR>"])
        while True:
            message = capture.unpack(ui.process.stdout)
            if message[0] == 2 and message[1] == "notification-tools-test-prompt":
                break
            if message[0] == 2 and message[1] == "redraw":
                ui.redraw(message[2])
        keys("n")
        assert lua("return vim.g.confirm_result") == 2
        assert not any("lease-confirm" in r["message"] for r in lua("return tools.history()"))

        keys(":echoerr 'captured-error'<CR>")
        assert any("captured-error" in r["message"] and r["level"] == 4 for r in lua("return tools.history()"))
        before = lua("return #tools.history()")
        keys(":messages<CR>")
        assert lua("return vim.bo.filetype") == "notification-tools-history"
        assert "native-before" in lua("return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')")
        if lua("return vim.fn.has('nvim-0.12') == 1"):
            word_color("NativeWord", 0x11aaee)
        assert lua("return #tools.history()") == before
        keys("<CR>")
        assert lua("return vim.b.notification_tools_detail")
        keys("q")

        # Release in order, then check actual original cmdline/message rendering.
        lua("lease:detach(); provider.stop(); tools.dismiss()")
        assert lua("return not lease:is_active() and vim.o.cmdheight == 1")
        keys(":echo")
        assert ":echo" in screen().splitlines()[-1], screen()
        keys(" 'native-after'<CR>")
        assert "native-after" in screen(), screen()
        assert lua("return #tools.history()") == before
        lua("tools.teardown()")
        print("messages UI: native fallback, separate cmdline renderer, nested input/confirm, errors, native history and release passed")
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == "__main__":
    main()
