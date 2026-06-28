# Run the Color Harmonizer batch report on Windows.
# Usage:  ./scripts/run_reports.ps1                 (uses 'godot' on PATH)
#         ./scripts/run_reports.ps1 -Godot "C:\path\to\Godot_v4.7-stable.exe"
param(
    [string]$Godot = "godot",
    [string]$Scenes = "res://demo",
    [string]$Profile = "res://addons/color_harmonizer/profiles/default.tres",
    [string]$Out = "res://color_reports",
    [int]$MinScore = 55
)

& $Godot --path . "res://addons/color_harmonizer/batch/batch.tscn" -- `
    "--scenes-dir=$Scenes" "--profile=$Profile" "--out=$Out" "--min-score=$MinScore"

Write-Host "Exit code: $LASTEXITCODE"
exit $LASTEXITCODE
