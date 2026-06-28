#!/usr/bin/env bash
# Run the Color Harmonizer batch report on Linux / CI.
# Needs a real renderer, so we wrap with xvfb-run (a virtual display) rather
# than Godot's --headless, which uses a dummy driver and renders nothing.
#
# Usage:  ./scripts/run_reports.sh            (uses 'godot' on PATH)
#         GODOT=/path/to/godot ./scripts/run_reports.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
SCENES="${SCENES:-res://demo}"
PROFILE="${PROFILE:-res://addons/color_harmonizer/profiles/default.tres}"
OUT="${OUT:-res://color_reports}"
MIN_SCORE="${MIN_SCORE:-55}"

xvfb-run -a "$GODOT" --path . res://addons/color_harmonizer/batch/batch.tscn -- \
  "--scenes-dir=${SCENES}" "--profile=${PROFILE}" "--out=${OUT}" "--min-score=${MIN_SCORE}"
