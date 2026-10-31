#!/usr/bin/env bash
# Kills the example app four ways (Java crash, native crash, OOM, ANR) on a
# device or emulator, restarts it and prints the exit records the system kept.
#
# usage: tool/crash_scenarios.sh SERIAL
# The example app must be installed (a release build starts fastest):
#   (cd example && flutter build apk --release && adb -s SERIAL install -r build/app/outputs/flutter-apk/app-release.apk)
set -euo pipefail

S=$1
P=io.github.zalexei.app_diagnostics_example
UI="$(dirname "$0")/ui.py"

launch() {
  adb -s "$S" shell am start -n "$P/.MainActivity" >/dev/null
  for _ in $(seq 1 40); do
    sleep 1
    if "$UI" "$S" labels 2>/dev/null | grep -q "Reload"; then
      # The activity may come back scrolled down: scroll up to the crash lab.
      for _ in $(seq 1 8); do
        "$UI" "$S" labels 2>/dev/null | grep -q "Java crash" && return
        adb -s "$S" shell input swipe 540 700 540 2000 150
      done
      echo "crash lab buttons not found" >&2
      exit 1
    fi
  done
  echo "the app did not start" >&2
  exit 1
}

wait_dead() {
  for _ in $(seq 1 40); do
    sleep 1
    [ -z "$(adb -s "$S" shell pidof "$P" || true)" ] && return
  done
  echo "the process is still alive" >&2
  exit 1
}

for kind in "Java crash" "Native crash" "OOM"; do
  launch
  "$UI" "$S" tap "$kind"
  wait_dead
done

launch
"$UI" "$S" tap "ANR"
sleep 2
adb -s "$S" shell input tap 540 300 # a pending input event turns the frozen main thread into an ANR
for _ in $(seq 1 30); do
  sleep 1
  "$UI" "$S" labels 2>/dev/null | grep -q "Close app" && break
done
"$UI" "$S" tap "Close app"
wait_dead

launch
adb -s "$S" shell dumpsys activity exit-info "$P" | grep -E "reason=" | head -4
