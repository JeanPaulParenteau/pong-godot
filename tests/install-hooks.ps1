# Point git at the committed hooks/ dir so pre-push runs the test suite.
# Run once after cloning.
$root = (git rev-parse --show-toplevel)
git -C $root config core.hooksPath hooks
Write-Host "Git hooks installed (core.hooksPath=hooks). Pre-push now runs tests + the coverage gate."
Write-Host "Set `$env:GODOT to your Godot binary if it isn't on PATH."
