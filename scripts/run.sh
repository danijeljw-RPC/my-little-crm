#!/usr/bin/env zsh
# Run the Flutter app on a chosen device.
#
#   scripts/run.sh                      list everything you can run on
#   scripts/run.sh "<name or id>"       run there (boots simulators/emulators if needed)
#   scripts/run.sh "<target>" --release extra args go straight to `flutter run`
#
# Examples: scripts/run.sh macos | scripts/run.sh chrome | scripts/run.sh "iPhone 18 Pro"
#           scripts/run.sh swoovr-pixel | scripts/run.sh R9WW30CSG1K

set -euo pipefail
cd "${0:A:h}/.."

if ! command -v flutter >/dev/null 2>&1; then
  print -u2 "error: flutter is not on PATH"
  exit 1
fi

is_mac=false
[[ $OSTYPE == darwin* ]] && command -v xcrun >/dev/null 2>&1 && is_mac=true

# "name|id" for each running/connected device.
running_devices() {
  flutter devices 2>/dev/null | awk -F ' • ' 'NF >= 3 {
    name = $1; id = $2
    gsub(/^[ \t]+|[ \t]+$/, "", name); gsub(/^[ \t]+|[ \t]+$/, "", id)
    print name "|" id
  }'
}

# Launchable emulator ids (Android AVDs, generic iOS simulator).
emulator_ids() {
  flutter emulators 2>/dev/null | awk -F ' • ' 'NF >= 3 && $1 !~ /^Id/ {
    id = $1; gsub(/^[ \t]+|[ \t]+$/, "", id); print id
  }'
}

# "name|udid" for each shut-down iOS simulator.
shutdown_simulators() {
  $is_mac || return 0
  xcrun simctl list devices available 2>/dev/null |
    sed -nE 's/^ +(.+) \(([0-9A-F-]{36})\) \(Shutdown\).*$/\1|\2/p'
}

# Print the device id matching $1: exact id, then exact name, then substring.
find_running() {
  local target=${1:l} line name id
  local -a devices=("${(@f)$(running_devices)}")
  for line in $devices; do id=${line#*|}; [[ ${id:l} == $target ]] && { print -r -- $id; return 0; }; done
  for line in $devices; do
    name=${line%%|*}; name=${name% \(*\)}; name=${name% \(*\)}
    [[ ${name:l} == $target ]] && { print -r -- ${line#*|}; return 0; }
  done
  for line in $devices; do [[ ${line:l} == *$target* ]] && { print -r -- ${line#*|}; return 0; }; done
  return 1
}

show_simulator_window() {
  open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true
}

# Wait until a device id not in $1 (newline list) shows up; print it.
wait_for_new_device() {
  local before=$1 waited=0 line id
  while (( waited < 180 )); do
    for line in "${(@f)$(running_devices)}"; do
      id=${line#*|}
      [[ -n $id && $'\n'$before$'\n' != *$'\n'$id$'\n'* ]] && { print -r -- $id; return 0; }
    done
    sleep 3; (( waited += 3 ))
  done
  return 1
}

list_targets() {
  print "== Running / connected devices =="
  local line
  for line in "${(@f)$(running_devices)}"; do
    [[ -n $line ]] && printf '  %-34s id: %s\n' "${line%%|*}" "${line#*|}"
  done
  print "\n== Emulators (launched for you) =="
  local -a emus=("${(@f)$(emulator_ids)}")
  if [[ -n ${emus[1]:-} ]]; then for line in $emus; do print "  $line"; done; else print "  (none)"; fi
  if $is_mac; then
    print "\n== iOS simulators, shut down (booted for you) =="
    local -a sims=("${(@f)$(shutdown_simulators)}")
    if [[ -n ${sims[1]:-} ]]; then for line in $sims; do print "  ${line%%|*}"; done; else print "  (none)"; fi
  fi
  print "\nUsage: scripts/run.sh \"<name or id>\" [flutter run args]"
  print "   eg: scripts/run.sh macos   scripts/run.sh chrome   scripts/run.sh \"iPhone 18 Pro\""
}

if (( $# == 0 )); then
  list_targets
  exit 0
fi

target=$1; shift

# 1. Already running or connected.
if device=$(find_running "$target"); then
  print "▶ Running on $device"
  exec flutter run -d "$device" "$@"
fi

# 2. A shut-down iOS simulator (match by name or UDID).
if $is_mac; then
  for line in "${(@f)$(shutdown_simulators)}"; do
    [[ -z $line ]] && continue
    name=${line%%|*}; udid=${line#*|}
    if [[ ${name:l} == ${target:l} || $udid == ${target:u} ]]; then
      print "⏻ Booting iOS simulator $name"
      xcrun simctl boot "$udid"
      show_simulator_window
      exec flutter run -d "$udid" "$@"
    fi
  done
fi

# 3. A launchable emulator (Android AVD, or the generic iOS simulator).
for emu in "${(@f)$(emulator_ids)}"; do
  if [[ -n $emu && ${emu:l} == ${target:l} ]]; then
    before=$(running_devices | cut -d'|' -f2)
    print "⏻ Launching emulator $emu (waiting up to 3 min)…"
    flutter emulators --launch "$emu" >/dev/null
    if device=$(wait_for_new_device "$before"); then
      print "▶ Running on $device"
      exec flutter run -d "$device" "$@"
    fi
    print -u2 "error: emulator $emu did not come up in time"
    exit 1
  fi
done

print -u2 "error: no device, simulator or emulator matches \"$target\"\n"
list_targets >&2
exit 1
