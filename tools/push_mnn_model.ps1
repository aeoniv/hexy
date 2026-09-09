# Gives Hexy a mind.
#
# MNN models are hundreds of megabytes and never ride in the APK. IxMnn reads
# them from the app's external files dir instead:
#
#   /storage/emulated/0/Android/data/app.ix64.hexy/files/<model>/config.json
#
# That directory belongs to the install, so every uninstall/reinstall quietly
# takes the mind away and the seam falls back to `backend=mock`. Re-run this
# after any reinstall. It is idempotent: files already there at the right size
# are skipped.
#
# Usage:
#   ./tools/push_mnn_model.ps1                       # embed only (both phones)
#   ./tools/push_mnn_model.ps1 -Model chat           # chat only
#   ./tools/push_mnn_model.ps1 -Model all -Serial RFCT71BW9YV
#   ./tools/push_mnn_model.ps1 -Model vision -Serial RFCT71BW9YV   # Fold only
#   ./tools/push_mnn_model.ps1 -Model chat35 -Serial RFCT71BW9YV   # the 0.8B
#
# The models live OUTSIDE the repo at $Root below and come from the taobao-mnn
# org on HuggingFace, which publishes MNN's own exports:
#
#   gte-embedding-mnn  <- taobao-mnn/gte_sentence-embedding_multilingual-base-MNN
#                         (768-dim, BERT-style; MNN's Embedding class requires
#                          a model whose output is named `sentence_embeddings`,
#                          which the Qwen3-Embedding exports are not)
#   qwen3-0.6b-mnn     <- taobao-mnn/Qwen3-0.6B-MNN  (int4, ~450 MB of weights)
#   qwen2-vl-2b-mnn    <- taobao-mnn/Qwen2-VL-2B-Instruct-MNN  (~1.71 GB, Phase 9)
#   qwen3.5-0.8b-mnn   <- taobao-mnn/Qwen3.5-0.8B-MNN  (int4, ~548 MB total)
#
# THE 0.8B IS ONE DIRECTORY THAT IS BOTH MOUTH AND EYES. `visual.mnn` and
# `visual.mnn.weight` (63 MB) ride beside the llm pair, so the pack that answers
# is the pack that looks — once it is smoked on device it can retire the 1.71 GB
# Qwen2-VL lane for Phase 9 vision and save a gigabyte. Until then it is chat.
# It also ships `llm.mnn.json` (5.3 MB), which Qwen3-0.6B does not have; MNN
# 3.6.1 reads it and a pack pushed without it is a pack that will not load.
# Thinking is not a prompt switch here: `config.json` carries
# `jinja.context.enable_thinking` (shipped `true`; the Fold run of 2026-09-06
# pushed it `false` — see Phase 11c) and the `<think>` tags are separated by the
# seam. It is NOT in `llm_config.json`, which only mentions the name inside its
# Jinja template. Do NOT append Qwen3's `/no_think` to it.
#
# gte-embedding-mnn stays the embed model. Nothing about a chat pack changes
# that: MNN's `Embedding` class needs an output named `sentence_embeddings` and
# the Qwen3-Embedding exports do not have one.
#
# THE VISION LANE IS FOLD-ONLY AND IS NOT IN `all`. It is ~1.71 GB, and
# ModelStore refuses to plan or load it on a phone with less than 6 GiB of
# physical RAM (the A22), so pushing it there would only fill a card up. Ask
# for it by name: `-Model vision`.
#
# Its file list is NOT enumerated here: `files = @()` means "everything in that
# directory", because the VL export ships an embeddings blob and a second
# (visual) graph beside the llm pair and a hard-coded list is one renamed file
# away from a half-pushed model that loads and then answers nonsense.
#
# Re-download with, per file:
#   curl -L -o <file> https://huggingface.co/taobao-mnn/<repo>/resolve/main/<file>

# -Model, -Serial and -Root are the SHARED flag block: the same five lane names
# and the same default root that tools/publish_assets.ps1 takes, so a word means
# one thing across the tools. The list is stated twice only because PowerShell
# requires a ValidateSet literal in the param block; tools/_common.ps1 holds the
# copy both scripts are checked against, along with the adb path and the -s
# argument shape that used to live only here.
param(
    [ValidateSet("embed", "chat", "chat35", "vision", "all")][string]$Model = "embed",
    [string]$Serial = "",
    [string]$Root = "")

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_common.ps1")
if (-not $Root) { $Root = $IxModelRoot }
$pkg = $IxPackage
$base = "/storage/emulated/0/Android/data/$pkg/files"

$sets = @{
    embed = @{ dir = "gte-embedding-mnn"
               files = @("config.json", "llm_config.json", "tokenizer.txt",
                         "embedding.mnn", "embeddings_bf16.bin") }
    chat  = @{ dir = "qwen3-0.6b-mnn"
               files = @("config.json", "llm_config.json", "tokenizer.txt",
                         "llm.mnn", "llm.mnn.weight") }
    # THE 0.8B, ENUMERATED. Unlike the VL pack this list is complete and known,
    # and every name in it is load-bearing: no llm.mnn.json, no load.
    chat35 = @{ dir = "qwen3.5-0.8b-mnn"
                files = @("config.json", "llm_config.json", "tokenizer.txt",
                          "llm.mnn", "llm.mnn.json", "llm.mnn.weight",
                          "visual.mnn", "visual.mnn.weight") }
    vision = @{ dir = "qwen2-vl-2b-mnn"
                files = @() }
}
$wanted = if ($Model -eq "all") { $IxDefaultLanes } else { @($Model) }

foreach ($key in $wanted) {
    $set = $sets[$key]
    $src = Join-Path $Root $set.dir
    if (-not (Test-Path $src)) {
        Write-Error "no model at $src - see the header of this script for where it comes from"
    }
    # An empty list means the whole directory, sorted so a run is reproducible
    # and config.json (the file the loader gates on) is pushed with the rest
    # rather than first: a config that landed alone would make a half-pushed
    # model look ready.
    $files = if ($set.files.Count -gt 0) { $set.files } else {
        Get-ChildItem -Path $src -File | Sort-Object Name | ForEach-Object { $_.Name }
    }
    if ($files.Count -eq 0) { Write-Error "nothing to push in $src" }
    $dst = "$base/$($set.dir)"
    Invoke-IxAdb -Serial $Serial shell "mkdir -p '$dst'" | Out-Null
    foreach ($f in $files) {
        $local = Join-Path $src $f
        if (-not (Test-Path $local)) { Write-Error "missing $local" }
        $size = (Get-Item $local).Length
        $there = Get-IxRemoteSize -Serial $Serial -Path "$dst/$f"
        if ($there -eq "$size") {
            Write-Host "ok    $($set.dir)/$f ($size bytes)"
            continue
        }
        Write-Host "push  $($set.dir)/$f ($size bytes)"
        Invoke-IxAdb -Serial $Serial push $local "$dst/$f" | Out-Null
    }
}

Invoke-IxAdb -Serial $Serial shell "ls -la '$base'"
Write-Host "restart Hexy - logcat should show 'mnn embed: dim=768' (and 'mnn chat: ...' if chat was pushed)."
if ($wanted -contains "vision") {
    Write-Host "vision: turn the VISION toggle on in the workshop, then run the `"look test`" - the first device run has to confirm the BGR channel order and the box scale."
}
