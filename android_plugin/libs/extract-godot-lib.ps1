# Extracts the Godot 4.7.1 Android library the plugin compiles against.
#
# The AAR is not published to MavenCentral at 4.7.1 and is not a loose file in
# the export templates — it lives inside android_source.zip. Pull it out once.
# Not committed: it is ~100 MB of engine binary (see .gitignore).
$ErrorActionPreference = "Stop"
$zip = Join-Path $env:APPDATA "Godot\export_templates\4.7.1.stable\android_source.zip"
$dst = Join-Path $PSScriptRoot "godot-lib.template_release.aar"
if (Test-Path $dst) { Write-Host "already present: $dst"; exit 0 }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
	$entry = $archive.Entries | Where-Object { $_.FullName -eq "libs/release/godot-lib.template_release.aar" }
	if (-not $entry) { throw "godot-lib not found in $zip" }
	[IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dst, $true)
	Write-Host "extracted: $dst"
} finally {
	$archive.Dispose()
}
