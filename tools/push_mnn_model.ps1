# Push Alibaba MNN Qwen & GTE models to Android device.
# Usage:
#   powershell ./tools/push_mnn_model.ps1 -Model qwen
#   powershell ./tools/push_mnn_model.ps1 -Model embed
#   powershell ./tools/push_mnn_model.ps1 -Model all

param(
    [ValidateSet("embed", "qwen", "all")][string]$Model = "all",
    [string]$Serial = ""
)

$pkg = "app.ix64.hexy"
$dstBase = "/storage/emulated/0/Android/data/$pkg/files"

$adbArgs = if ($Serial) { @("-s", $Serial) } else { @() }

function Invoke-Adb {
    param([string[]]$cmd)
    & adb @adbArgs @cmd
}

Write-Host "Ensuring destination directory on device: $dstBase"
Invoke-Adb shell "mkdir -p '$dstBase'"

$modelsRoot = "$env:USERPROFILE/Downloads/mnn_models"
if (-not (Test-Path $modelsRoot)) {
    $modelsRoot = "D:/models/mnn"
}

Write-Host "Looking for MNN models at: $modelsRoot"

if ($Model -eq "qwen" -or $Model -eq "all") {
    $srcQwen = "$modelsRoot/qwen3-0.6b-mnn"
    if (Test-Path $srcQwen) {
        Write-Host "Pushing Qwen model..."
        Invoke-Adb push $srcQwen "$dstBase/"
    } else {
        Write-Warning "Qwen model folder not found at: $srcQwen"
    }
}

if ($Model -eq "embed" -or $Model -eq "all") {
    $srcEmbed = "$modelsRoot/gte-embedding-mnn"
    if (Test-Path $srcEmbed) {
        Write-Host "Pushing GTE Embedding model..."
        Invoke-Adb push $srcEmbed "$dstBase/"
    } else {
        Write-Warning "GTE model folder not found at: $srcEmbed"
    }
}

Write-Host "Done! Device model directory status:"
Invoke-Adb shell "ls -la '$dstBase'"
