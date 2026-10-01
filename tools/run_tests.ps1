# Thin wrapper: import the project, then run tools/run_tests.gd headless.
# $env:GODOT points at the Godot 4.7.1 console binary (default: `godot` on PATH).
# Extra arguments are substring filters passed to the runner.
$godot = if ($env:GODOT) { $env:GODOT } else { 'godot' }
$root = Split-Path -Parent $PSScriptRoot
& $godot --headless --path $root --import *> $null
& $godot --headless --path $root -s res://tools/run_tests.gd -- @args
exit $LASTEXITCODE
