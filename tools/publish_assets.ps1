# Puts Hexy's mind somewhere a stranger's phone can reach it.
#
# The two MNN model dirs are ~900 MB together and are not in the APK: that is
# nine times what Play delivers in one package. Until now the only way onto a
# device was `tools/push_mnn_model.ps1` over adb from this machine - which works
# for the two phones on this desk and for nobody else. This uploads the same
# bytes to a public bucket and writes the MANIFEST the app reads on first run
# (scripts/net/asset_bootstrap.gd).
#
#   ./tools/publish_assets.ps1                 # upload + regenerate manifest
#   ./tools/publish_assets.ps1 -ManifestOnly   # just re-checksum and re-publish
#   ./tools/publish_assets.ps1 -Model chat     # one lane only
#   ./tools/publish_assets.ps1 -Model chat35   # the 0.8B, opt-in, never in `all`
#
# The manifest is the contract. Every entry carries the sha256 of the exact
# bytes uploaded, so a truncated or tampered download is REJECTED by the phone
# rather than handed to MNN, which would map it and die in native code. That is
# why the checksums are always taken from the LOCAL source and the upload is the
# default: regenerating the manifest without re-uploading is only safe when the
# local file is byte-identical to the remote one.
#
# Hosting: a plain GCS bucket in the Firebase project ix64-havata, shared with
# ix64-avatar (which publishes under models/v1; hexy is under hexy/v1). Public
# read (allUsers -> roles/storage.objectViewer), writes need the owner's gcloud
# credentials. See README.md ("First-run asset delivery").
# -Model and -Root are the SHARED flag block: the same five lane names and the
# same default root that tools/push_mnn_model.ps1 takes. `vision` validates here
# and is then refused by name below - a 1.71 GB Fold-only pack has no business in
# the bucket every phone reads, and saying so out loud beats the parameter binder
# saying the word does not exist. The list is stated twice only because
# PowerShell requires a ValidateSet literal in the param block; tools/_common.ps1
# holds the copy both scripts are checked against.
param(
    [ValidateSet("embed", "chat", "chat35", "vision", "all")][string]$Model = "all",
    [string]$Bucket = "ix64-havata-assets",
    [string]$Prefix = "hexy/v1",
    [string]$Root = "",
    [switch]$ManifestOnly,
    [string]$Out = "")

# Deliberately NOT "Stop": every gcloud call writes progress to stderr, and under
# Stop PowerShell turns a native command's first stderr line into a terminating
# NativeCommandError - the upload is then reported as a failure it did not have.
# Exit codes are checked explicitly instead, which is the thing that is actually
# true about whether a transfer worked.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_common.ps1")
if (-not $Root) { $Root = $IxModelRoot }
Assert-IxLaneSupported -Model $Model -Supported @("embed", "chat", "chat35", "all") -Why "the vision pack is 1.71 GB and Fold-only; push it over adb with tools/push_mnn_model.ps1 -Model vision"
# Composite uploads split the object and reassemble it server-side. The bytes are
# identical, but the object then has no whole-file MD5, and this script's whole
# claim is about a digest - so it is turned off and the manifest's sha256 is the
# only integrity story, end to end.
$env:CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_ENABLED = "False"
$env:CLOUDSDK_CORE_DISABLE_PROMPTS = "1"
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Out) { $Out = Join-Path $repo "config\asset_manifest.json" }
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
$base = "https://storage.googleapis.com/$Bucket/$Prefix/"

# lane : which model dir wants it. A build with no such lane SKIPS the entry
#        instead of spending half a gigabyte of somebody's data on weights it
#        cannot open - see AssetManifest.wanted() in the app.
# dir  : the directory name, on this disk AND on the phone. IxMnn resolves it
#        against getExternalFilesDir(null); ModelStore.LANE_DIRS is the app's
#        copy of these two strings and must match.
# files: every file MNN needs. Listed rather than globbed, so an unrelated file
#        that wanders into the source dir is not published as part of the model.
$sets = @(
    @{ lane = "embed"; key = "embed"; dir = "gte-embedding-mnn"
       files = @("config.json", "llm_config.json", "tokenizer.txt",
                 "embedding.mnn", "embeddings_bf16.bin") },
    @{ lane = "chat";  key = "chat";  dir = "qwen3-0.6b-mnn"
       files = @("config.json", "llm_config.json", "tokenizer.txt",
                 "llm.mnn", "llm.mnn.weight") },
    # PHASE 11c - THE 0.8B, AND IT IS NOT IN `all`. It is an OPTIONAL lane in
    # ModelStore, so a phone only fetches it when it asks by name; publishing it
    # beside the two every phone plans would put 548 MB in the bucket that the
    # default plan never reads. Ask for it: `-Model chat35`.
    # Every name below is load-bearing - no llm.mnn.json, no load - and
    # visual.* rides along because this one directory is also the eyes.
    @{ lane = "chat35"; key = "chat35"; dir = "qwen3.5-0.8b-mnn"
       files = @("config.json", "llm_config.json", "tokenizer.txt",
                 "llm.mnn", "llm.mnn.json", "llm.mnn.weight",
                 "visual.mnn", "visual.mnn.weight") }
)
if ($Model -ne "all") { $sets = $sets | Where-Object { $_.key -eq $Model } }

$specs = @()
foreach ($set in $sets) {
    foreach ($f in $set.files) {
        $specs += @{
            name = "$($set.dir)/$f"
            src  = Join-Path (Join-Path $Root $set.dir) $f
            lane = $set.lane
        }
    }
}

foreach ($s in $specs) {
    if (-not (Test-Path $s.src)) {
        Write-Host "missing source: $($s.src) - see the header of tools/push_mnn_model.ps1 for where each file comes from"
        exit 1
    }
}

$assets = @()
foreach ($s in $specs) {
    $item = Get-Item $s.src
    Write-Host "hashing $($s.name) ($($item.Length) bytes)..."
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $s.src).Hash.ToLower()
    $remote = "gs://$Bucket/$Prefix/$($s.name)"

    if (-not $ManifestOnly) {
        # Skip the upload when the object already carries these exact bytes, so a
        # second run does not re-push 450 MB to prove nothing changed.
        $there = (& gcloud storage objects describe $remote --format="value(size)" 2>$null | Out-String).Trim()
        if ($there -eq "$($item.Length)") {
            Write-Host "  already uploaded ($there bytes) - skipping"
        } else {
            Write-Host "  uploading -> $remote"
            & gcloud storage cp $s.src $remote
            if ($LASTEXITCODE -ne 0) { Write-Host "UPLOAD FAILED for $($s.name)"; exit 1 }
        }
        # Cache hard: these objects are immutable under a versioned prefix.
        & gcloud storage objects update $remote --cache-control="public, max-age=31536000, immutable" --custom-metadata="sha256=$sha" | Out-Null
    }

    $assets += [ordered]@{
        name            = $s.name
        lane            = $s.lane
        url             = "$base$($s.name)"
        size            = $item.Length
        sha256          = $sha
        required        = $true
        min_app_version = "0.0.0"
    }
}

$manifest = [ordered]@{
    manifest_version = 1
    generated        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    base_url         = $base
    assets           = $assets
}

# NO BOM. `Set-Content -Encoding utf8` on Windows PowerShell 5.1 writes a byte
# order mark, and three bytes of it in front of the '{' are enough to make
# Godot's JSON.parse_string refuse the whole manifest - a first run that fetches
# nothing and reports "you need nothing". (AssetManifest.parse strips one anyway;
# both ends are belt and braces, because neither is the only writer.) Written
# through .NET so the encoding is stated rather than inherited.
[IO.File]::WriteAllText($Out, ($manifest | ConvertTo-Json -Depth 6),
    (New-Object Text.UTF8Encoding $false))
Write-Host "wrote $Out"

# The manifest itself must NOT be cached: it is the one mutable object here, and
# a phone holding a day-old copy would keep chasing an asset that moved.
$manifestRemote = "gs://$Bucket/$Prefix/asset_manifest.json"
& gcloud storage cp $Out $manifestRemote
if ($LASTEXITCODE -ne 0) { Write-Host "MANIFEST UPLOAD FAILED"; exit 1 }
& gcloud storage objects update $manifestRemote --cache-control="no-cache, max-age=0" --content-type="application/json" | Out-Null
Write-Host ""
Write-Host "manifest: ${base}asset_manifest.json"
