#!/usr/bin/env bash
# Thin wrapper: import the project, then run tools/run_tests.gd headless.
# GODOT points at the Godot 4.7.1 binary (default: `godot` on PATH).
# Extra arguments are substring filters passed to the runner.
set -eu
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path "$ROOT" -s res://tools/run_tests.gd -- "$@"
