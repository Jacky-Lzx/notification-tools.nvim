#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export TMPDIR="${TMPDIR:-/private/tmp}"
test_root=$(mktemp -d /private/tmp/notification-tools-tests.XXXXXX)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_root/state"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_DATA_HOME="$test_root/data"
for suite in tests/core.lua tests/routing.lua tests/integrations.lua tests/layout.lua tests/styles.lua tests/markdown.lua tests/history.lua tests/browsing.lua tests/task_history.lua; do
  nvim --headless -n -u NONE -i NONE --noplugin -l "$suite"
done
if [ -n "${NOTIFICATION_TOOLS_NOICE_ROOT:-}" ] && [ -n "${NOTIFICATION_TOOLS_NUI_ROOT:-}" ]; then
  nvim --headless -n -u NONE -i NONE --noplugin -l tests/noice.lua
fi
if [ -n "${NOTIFICATION_TOOLS_LAZY_ROOT:-}" ]; then
  nvim --headless -n -u NONE -i NONE --noplugin -l tests/lazy.lua
fi
stylua --check lua tests examples
