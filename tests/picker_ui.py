#!/usr/bin/env python3
"""Validate the notification component picker against Neovim's rendered UI."""
import importlib.util
import os
from pathlib import Path
import signal
import time

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("capture", ROOT / "scripts/screenshots.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def main():
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("Picker UI timed out")))
    signal.alarm(25)
    ui = capture.Capture(os.environ.copy())

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def settle(condition):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            done = lua("return " + condition)
            lua("vim.cmd.redraw()")
            ui.request("nvim_eval", ["1"])
            if done:
                return
        raise AssertionError("UI state did not settle: " + condition + "\n" + screen())

    def screen():
        return "\n".join("".join(cell[0] for cell in row) for row in ui.grid)

    try:
        ui.request("nvim_ui_attach", [140, 38, {"rgb": True, "ext_linegrid": True}])
        lua("""
            vim.opt.rtp:prepend(vim.fn.getcwd())
            vim.opt.rtp:append(vim.fn.getcwd() .. '/../selection-tools.nvim')
            vim.api.nvim_set_hl(0, 'PickerClock', {fg=0x12ab34})
            require('selection_tools').setup({
                matcher={backend='native'}, layout={width=0.95, height=0.8},
                component_defaults={time={hl='PickerClock'}},
            })
            tools=require('notification-tools')
            tools.setup({notify=false,timeout=0})
            tools.notify('中文🙂 needle first', 'warn', {title='Build',source='compiler'})
            tools.notify('needle second', 'error', {title='Server',source='lua_ls'})
            tools.dismiss()
            origin=vim.api.nvim_get_current_win()
            p=tools.pick_history()
        """)
        settle("vim.api.nvim_get_mode().mode == 'i' and not p.loading")
        assert "Build" in screen() and "needle" in screen(), screen()
        clock = lua("""
            for _, m in ipairs(vim.api.nvim_buf_get_extmarks(p.list_buf,-1,0,-1,{details=true})) do
                if m[4].hl_group == 'PickerClock' then
                    local pos=vim.api.nvim_win_get_position(p.list_win)
                    return {pos[1]+m[2],pos[2]+m[3]}
                end
            end
            error('Clock highlight missing')
        """)
        for _, attr in ui.grid[clock[0]][clock[1]:clock[1]+8]:
            assert ui.attrs.get(attr, {}).get("foreground", ui.fg) == 0x12AB34
        ui.request("nvim_input", ["needle"])
        settle("p.query == 'needle' and #p.matches == 2")
        lua("before=p.index; tick=vim.api.nvim_buf_get_changedtick(p.list_buf)")
        ui.request("nvim_input", ["<C-n>"])
        settle("p.index ~= before")
        assert lua("return vim.api.nvim_buf_get_changedtick(p.list_buf) == tick")
        assert "needle" in screen(), screen()
        ui.request("nvim_ui_try_resize", [46, 25])
        settle("vim.o.columns == 46 and vim.api.nvim_get_current_win() == p.input_win")
        assert lua("""
            for _, line in ipairs(vim.api.nvim_buf_get_lines(p.list_buf,0,-1,false)) do
                if vim.fn.strdisplaywidth(line) > p.resolved.width then return false end
            end
            return p.query == 'needle' and #p.matches == 2
        """)
        ui.request("nvim_input", ["<Esc>"])
        settle("p.closed and vim.api.nvim_get_current_win() == origin")
        assert lua("return #tools.history() == 2 and #vim.api.nvim_list_wins() == 1"), lua("return {history=tools.history(),windows=#vim.api.nvim_list_wins()}")
        print("Notification picker RPC UI: shared RGB time style, Unicode, burst search, selection movement, narrow resize and focus passed")
    finally:
        ui.close()
        signal.alarm(0)


if __name__ == "__main__":
    main()
