#!/usr/bin/env python3
"""Capture Neovim's actual RGB UI grid and export README PNGs.

No Python dependencies. Requires nvim and rsvg-convert; optional Catppuccin path
via NOTIFICATION_TOOLS_THEME_ROOT. UI colors/text/layout come from redraw events.
"""
import argparse
import html
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def pack(value):
    if value is None:
        return b"\xc0"
    if isinstance(value, bool):
        return b"\xc3" if value else b"\xc2"
    if isinstance(value, int):
        return b"\xd3" + struct.pack(">q", value)
    if isinstance(value, str):
        raw = value.encode()
        return b"\xdb" + struct.pack(">I", len(raw)) + raw
    if isinstance(value, (list, tuple)):
        return b"\xdd" + struct.pack(">I", len(value)) + b"".join(map(pack, value))
    if isinstance(value, dict):
        return b"\xdf" + struct.pack(">I", len(value)) + b"".join(pack(k) + pack(v) for k, v in value.items())
    raise TypeError(type(value))


def unpack(stream):
    def read(count):
        result = stream.read(count)
        if len(result) != count:
            raise EOFError("Neovim's RPC stream closed")
        return result

    def number(fmt):
        return struct.unpack(fmt, read(struct.calcsize(fmt)))[0]

    head = read(1)[0]
    if head < 0x80:
        return head
    if head >= 0xE0:
        return head - 256
    if 0xA0 <= head <= 0xBF:
        return read(head & 31).decode()
    if 0x90 <= head <= 0x9F:
        return [unpack(stream) for _ in range(head & 15)]
    if 0x80 <= head <= 0x8F:
        return {unpack(stream): unpack(stream) for _ in range(head & 15)}
    if head in (0xC0, 0xC2, 0xC3):
        return {0xC0: None, 0xC2: False, 0xC3: True}[head]
    formats = {0xCA: ">f", 0xCB: ">d", 0xCC: ">B", 0xCD: ">H", 0xCE: ">I", 0xCF: ">Q", 0xD0: ">b", 0xD1: ">h", 0xD2: ">i", 0xD3: ">q"}
    if head in formats:
        return number(formats[head])
    sizes = {0xC4: ">B", 0xC5: ">H", 0xC6: ">I", 0xD9: ">B", 0xDA: ">H", 0xDB: ">I", 0xDC: ">H", 0xDD: ">I", 0xDE: ">H", 0xDF: ">I", 0xC7: ">B", 0xC8: ">H", 0xC9: ">I"}
    if head in sizes:
        size = number(sizes[head])
        if head in (0xDC, 0xDD):
            return [unpack(stream) for _ in range(size)]
        if head in (0xDE, 0xDF):
            return {unpack(stream): unpack(stream) for _ in range(size)}
        if head in (0xC7, 0xC8, 0xC9):
            read(1)  # Extension type; API handle values are not used here.
        raw = read(size)
        return raw.decode() if head in (0xD9, 0xDA, 0xDB) else raw
    if 0xD4 <= head <= 0xD8:
        read(1)
        return read(1 << (head - 0xD4))
    raise ValueError(f"Unsupported MessagePack prefix: {head:#x}")


class Capture:
    def __init__(self, env):
        self.process = subprocess.Popen(["nvim", "--embed", "--clean", "-n"], cwd=ROOT, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.serial = 0
        self.grid = []
        self.attrs = {0: {}}
        self.fg, self.bg = 0xCDD6F4, 0x1E1E2E

    def redraw(self, events):
        for name, *calls in events:
            for args in calls:
                if name == "default_colors_set":
                    self.fg, self.bg = args[:2]
                elif name == "hl_attr_define":
                    self.attrs[args[0]] = args[1]
                elif name == "grid_resize" and args[0] == 1:
                    self.grid = [[(" ", 0)] * args[1] for _ in range(args[2])]
                elif name == "grid_clear" and args[0] == 1:
                    self.grid = [[(" ", 0)] * len(self.grid[0]) for _ in self.grid]
                elif name == "grid_line" and args[0] == 1:
                    _, row, col, cells, *_ = args
                    highlight = 0
                    for cell in cells:
                        char = cell[0]
                        if len(cell) > 1:
                            highlight = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            self.grid[row][col] = (char, highlight)
                            col += 1
                elif name == "grid_scroll" and args[0] == 1:
                    _, top, bottom, left, right, rows, cols = args
                    original = [row[:] for row in self.grid]
                    for row in range(top, bottom):
                        for col in range(left, right):
                            source_row, source_col = row + rows, col + cols
                            self.grid[row][col] = original[source_row][source_col] if top <= source_row < bottom and left <= source_col < right else (" ", 0)

    def request(self, method, args):
        self.serial += 1
        serial = self.serial
        self.process.stdin.write(pack([0, serial, method, args]))
        self.process.stdin.flush()
        while True:
            message = unpack(self.process.stdout)
            if message[0] == 2 and message[1] == "redraw":
                self.redraw(message[2])
            elif message[0] == 1 and message[1] == serial:
                if message[2] is not None:
                    raise RuntimeError(message[2])
                return message[3]

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()
        self.process.stderr.close()


def svg(capture, title, font):
    cell_width, cell_height = 10.5, 23
    padding, top = 28, 64
    width = len(capture.grid[0]) * cell_width + padding * 2
    height = len(capture.grid) * cell_height + top + padding
    color = lambda value: f"#{max(0, value):06x}"
    elements = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">', f'<rect width="{width}" height="{height}" rx="16" fill="{color(capture.bg)}"/>', f'<text x="{padding}" y="35" fill="#a6adc8" font-family="sans-serif" font-size="14" letter-spacing="1.4">{html.escape(title)}</text>', f'<g font-family="{html.escape(font, quote=True)}" font-size="17" xml:space="preserve">']
    backgrounds, foregrounds = [], []
    for row, cells in enumerate(capture.grid):
        for col, (char, attr_id) in enumerate(cells):
            attr = capture.attrs.get(attr_id, {})
            fg, bg = attr.get("foreground", capture.fg), attr.get("background", capture.bg)
            if attr.get("reverse"):
                fg, bg = bg, fg
            x, y = padding + col * cell_width, top + row * cell_height
            if bg != capture.bg:
                backgrounds.append(f'<rect x="{x}" y="{y}" width="{cell_width + .1}" height="{cell_height + .1}" fill="{color(bg)}"/>')
            if not char or char.isspace():
                continue
            # Terminal box glyphs span a whole cell, including line spacing.
            cx, cy, radius = x + cell_width / 2, y + cell_height / 2, cell_width / 2
            box = {
                "─": f"M {x},{cy} H {x + cell_width}",
                "│": f"M {cx},{y} V {y + cell_height}",
                "╭": f"M {cx},{y + cell_height} V {cy + radius} Q {cx},{cy} {x + cell_width},{cy}",
                "╮": f"M {x},{cy} Q {cx},{cy} {cx},{cy + radius} V {y + cell_height}",
                "╰": f"M {cx},{y} V {cy - radius} Q {cx},{cy} {x + cell_width},{cy}",
                "╯": f"M {x},{cy} Q {cx},{cy} {cx},{cy - radius} V {y}",
            }
            if char in box:
                foregrounds.append(f'<path d="{box[char]}" fill="none" stroke="{color(fg)}" stroke-width="1.2"/>')
                continue
            if char == "▎":
                foregrounds.append(f'<rect x="{x}" y="{y}" width="{cell_width / 4}" height="{cell_height}" fill="{color(fg)}"/>')
                continue
            style = (' font-weight="bold"' if attr.get("bold") else '') + (' font-style="italic"' if attr.get("italic") else '')
            decoration = 'text-decoration="underline"' if attr.get("underline") else 'text-decoration="line-through"' if attr.get("strikethrough") else ''
            foregrounds.append(f'<text x="{x}" y="{y + 18}" fill="{color(fg)}"{style} {decoration}>{html.escape(char)}</text>')
    elements.extend(backgrounds)
    elements.extend(foregrounds)
    elements.extend(['</g>', '</svg>'])
    return '\n'.join(elements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".github/assets")
    parser.add_argument("--font", default="Cascadia Mono, monospace")
    args = parser.parse_args()
    for binary in ("nvim", "rsvg-convert"):
        if not shutil.which(binary):
            parser.error(f"{binary} is required")
    args.output.mkdir(parents=True, exist_ok=True)
    scenes = {"overview": "NOTIFICATION-TOOLS.NVIM  /  NOTIFICATIONS + PROGRESS", "history": "NOTIFICATION HISTORY  /  NEWEST FIRST", "history-source": "NOTIFICATION HISTORY  /  SOURCE ON THE CURSOR LINE"}
    with tempfile.TemporaryDirectory(prefix="notification-screenshots-") as temp:
        env = dict(os.environ, XDG_STATE_HOME=temp + "/state", XDG_CACHE_HOME=temp + "/cache", XDG_DATA_HOME=temp + "/data")
        for scene, title in scenes.items():
            capture = Capture(env)
            try:
                capture.request("nvim_ui_attach", [112, 32, {"rgb": True, "ext_linegrid": True}])
                capture.request("nvim_exec_lua", ["vim.g.notification_screenshot_scene = ...; dofile('scripts/screenshot-scene.lua')", [scene]])
                capture.request("nvim_exec_lua", ["vim.wait(180); vim.cmd.redraw()", []])
                # A second request drains redraw notifications queued by the redraw.
                capture.request("nvim_eval", ["1"])
                visible = '\n'.join(''.join(cell[0] for cell in row) for row in capture.grid)
                assert ("Indexing workspace" if scene == "overview" else "Inlay Hints") in visible, visible
                if scene == "history":
                    assert "**Inlay Hints**" not in visible
                elif scene == "history-source":
                    assert "**Inlay Hints**" in visible
                source = Path(temp) / (scene + ".svg")
                source.write_text(svg(capture, title, args.font))
                target = args.output / (scene + ".png")
                subprocess.run(["rsvg-convert", "--zoom", "1.5", "--output", str(target), str(source)], check=True)
                print(f"Saved {target.relative_to(ROOT) if target.is_relative_to(ROOT) else target}")
            finally:
                capture.close()


if __name__ == "__main__":
    main()
