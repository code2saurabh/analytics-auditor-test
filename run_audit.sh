#!/usr/bin/env bash
set -x

# ============================================================================
#  Screen-reading tapper (RACE-PROOF) + corner tapper + timeout-guarded logs.
#
#  tap    waits for a button to appear, then taps it (fixes the consent race).
#  tapat  taps a screen corner by position, for unlabelled icons (eBay's X).
#  Log collection is wrapped in `timeout` so a flaky emulator that drops its
#  connection at the end can never hang the whole run; we still write the HAR.
# ============================================================================

TAP_TIMEOUT="${TAP_TIMEOUT:-30}"   # how long a "tap" waits for its target

# ui_dump : snapshot everything on screen into ./ui.xml (retry on animation)
ui_dump() {
  for _ in 1 2 3 4 5; do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml ui.xml >/dev/null 2>&1
    [ -s ui.xml ] && return 0
    sleep 1
  done
  return 1
}

# find_xy "words" : print "x y" of the centre of the first matching element.
# Accent- and case-insensitive, so "Akceptuje" matches "Akceptuję".
find_xy() {
  python3 - "$1" <<'PYE'
import sys, re, unicodedata
def flat(t):
    t = unicodedata.normalize('NFKD', t or '')
    return ''.join(c for c in t if not unicodedata.combining(c)).casefold()
want = flat(sys.argv[1])
try:
    xml = open('ui.xml', encoding='utf-8').read()
except Exception:
    sys.exit()
for m in re.finditer(r'<node[^>]*?>', xml):
    tag = m.group(0)
    tm = re.search(r'text="([^"]*)"', tag)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    hay = flat((tm.group(1) if tm else "") + " " + (dm.group(1) if dm else ""))
    if want in hay and hay.strip():
        bm = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if bm:
            x1, y1, x2, y2 = map(int, bm.groups())
            print(f"{(x1 + x2) // 2} {(y1 + y2) // 2}")
            break
PYE
}

# tap_once : one look, one tap. 0 if tapped, 1 if not found.
tap_once() {
  ui_dump || return 1
  local coords
  coords="$(find_xy "$1")"
  if [ -n "$coords" ]; then
    echo "TAP  '$1'  at  $coords"
    adb shell input tap $coords
    return 0
  fi
  return 1
}

# wait_and_tap : keep re-checking until the element appears, then tap it.
wait_and_tap() {
  local want="$1" timeout="${2:-$TAP_TIMEOUT}" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if tap_once "$want"; then
      echo "     (found after ${waited}s)"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "FAIL '$want'  never appeared within ${timeout}s"
  local safe="${want// /_}"
  cp ui.xml "ui-fail-${safe}.xml" 2>/dev/null || true
  adb exec-out screencap -p > "ui-fail-${safe}.png" 2>/dev/null || true
  return 1
}

# tapat : tap a screen corner by position, for icons that have no text.
#   positions: top-left  top-right  bottom-left  bottom-right  center
tapat() {
  local pos="$1" size w h x y
  size=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tail -1)
  w=${size%x*}; h=${size#*x}
  if [ -z "$w" ] || [ -z "$h" ]; then echo "tapat: could not read screen size"; return 1; fi
  case "$pos" in
    top-left)     x=$((w*8/100));  y=$((h*6/100))  ;;
    top-right)    x=$((w*92/100)); y=$((h*6/100))  ;;
    bottom-left)  x=$((w*8/100));  y=$((h*94/100)) ;;
    bottom-right) x=$((w*92/100)); y=$((h*94/100)) ;;
    center)       x=$((w/2));      y=$((h/2))      ;;
    *) echo "tapat: unknown position '$pos'"; return 1 ;;
  esac
  echo "TAPAT $pos at $x $y"
  adb shell input tap $x $y
}

# type_text "words" : type into whatever field is focused.
type_text() {
  echo "TYPE '$1'"
  adb shell input text "$(echo "$1" | sed 's/ /%s/g')"
}


adb root
sleep 5
adb wait-for-device

echo "=== Installing our certificate into the SYSTEM trust store ==="
adb shell "mkdir -p /data/local/tmp/cacerts && cp /system/etc/security/cacerts/* /data/local/tmp/cacerts/"
adb shell "mount -t tmpfs tmpfs /system/etc/security/cacerts"
adb shell "cp /data/local/tmp/cacerts/* /system/etc/security/cacerts/"

CERT_FILE=$(ls *.0 | head -n 1)
if [ -z "$CERT_FILE" ]; then
  echo "ERROR: no .0 certificate found. Files here:"
  ls -la
  exit 1
fi
echo "Using certificate: $CERT_FILE"
adb push "$CERT_FILE" /system/etc/security/cacerts/
adb shell "chmod 644 /system/etc/security/cacerts/$CERT_FILE"
adb shell "chown root:root /system/etc/security/cacerts/$CERT_FILE"
adb shell "ls /system/etc/security/cacerts/ | wc -l"

echo "=== Starting the recorder ==="
HAR_OUT=dump.har mitmdump -w dump.mitm -s har_dump.py > mitm.log 2>&1 &
PROXY_PID=$!
sleep 5

echo "=== Installing the app under test ==="
adb logcat -c
TARGET=test-apks/target.bin
INSTALL_OK=1

if [ -f "$TARGET" ]; then
  if unzip -l "$TARGET" | grep -q "\.apk\s*$"; then
    echo "Bundle detected - unpacking split APKs"
    mkdir -p /tmp/splits && unzip -o -q "$TARGET" -d /tmp/splits
    echo "--- splits found ---"
    ls -la /tmp/splits/*.apk
    echo "--- installing all splits together ---"
    adb install-multiple -r /tmp/splits/*.apk || INSTALL_OK=0
  else
    echo "Single APK detected"
    cp "$TARGET" /tmp/app.apk
    adb install -r /tmp/app.apk || INSTALL_OK=0
  fi
else
  echo "No external app supplied - auditing our own test app"
  adb install -r app/build/outputs/apk/debug/app-debug.apk || INSTALL_OK=0
fi

if [ "$INSTALL_OK" = "0" ]; then
  echo "############################################################"
  echo "INSTALL FAILED. This is a RESULT, not a mistake."
  echo "If it says INSTALL_FAILED_NO_MATCHING_ABIS, the app ships"
  echo "ARM-only code and will not run on this Intel emulator."
  echo "############################################################"
fi

echo "=== Which package did we just install? ==="
PKG=$(adb shell pm list packages -3 | sed 's/package://' | tr -d '\r' | grep -v analyticsauditor | head -1)
if [ -z "$PKG" ]; then
  PKG=$(adb shell pm list packages -3 | sed 's/package://' | tr -d '\r' | head -1)
fi
if [ -z "$PKG" ]; then
  echo "ERROR: nothing is installed. Stopping."
  kill $PROXY_PID || true
  exit 1
fi
echo "PACKAGE UNDER TEST: $PKG"

echo "=== Firebase debug mode for that package ==="
adb shell setprop debug.firebase.analytics.app "$PKG"
adb shell setprop log.tag.FA VERBOSE
adb shell setprop log.tag.FA-SVC VERBOSE
adb shell getprop debug.firebase.analytics.app

echo "=== Launching ==="
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
sleep 15
adb exec-out screencap -p > screen-1-launch.png

if adb shell pidof "$PKG" > /dev/null 2>&1; then
  echo "App is running."
else
  echo "############################################################"
  echo "APP IS NOT RUNNING. It crashed or refused to start."
  echo "This is a RESULT. Check crash.log and screen-1-launch.png."
  echo "############################################################"
fi

echo "=== Running the journey ==="
# Verbs:  tap <text>   wait for that text, tap it
#         tapat <pos>  tap a corner (top-left/top-right/bottom-left/bottom-right/center)
#         type <words> type into the focused field
#         wait <n>     pause n seconds
#         key <name>   press a hardware key (back, enter, home)
STEP_NUM=0
run_step() {
  local verb="$1"; shift
  local arg="$*"
  case "$verb" in
    tap)   wait_and_tap "$arg" || true ;;
    tapat) tapat "$arg" || true ;;
    type)  type_text "$arg" ;;
    wait)  sleep "${arg:-2}" ;;
    key)   adb shell input keyevent "KEYCODE_$(echo "$arg" | tr a-z A-Z)" ;;
    *)     echo "unknown step: $verb $arg" ;;
  esac
  STEP_NUM=$((STEP_NUM+1))
  sleep 2
  adb exec-out screencap -p > "screen-step-$STEP_NUM.png"
}

if [ -n "$JOURNEY_STEPS" ]; then
  echo "$JOURNEY_STEPS" | tr ';' '\n' | while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    verb="$(echo "$line" | cut -d' ' -f1)"
    rest="$(echo "$line" | cut -s -d' ' -f2-)"
    echo "--- step: $verb | $rest ---"
    run_step "$verb" "$rest"
  done
else
  echo "No journey supplied - trying to dismiss a consent dialog."
  waited=0
  while [ "$waited" -lt "$TAP_TIMEOUT" ]; do
    for word in Accept Akceptuje Agree Zgadzam Allow OK Continue Got; do
      tap_once "$word" && break 2
    done
    sleep 2; waited=$((waited + 2))
  done
fi

sleep 5
adb exec-out screencap -p > screen-2-after-journey.png

echo "=== Backgrounding, then leaving the SDK alone to flush ==="
adb shell input keyevent KEYCODE_HOME || true
sleep 60

echo "=== Logs (timeout-guarded so a dead emulator cannot hang the run) ==="
timeout -k 10 60 adb logcat -d -s FA:V FA-SVC:V > firebase.log 2>&1 || true
timeout -k 10 60 adb logcat -d -s AndroidRuntime:E ActivityManager:E > crash.log 2>&1 || true
echo "--- last 20 lines of Firebase log ---"
tail -20 firebase.log || true
echo "--- any crashes ---"
grep -iE "FATAL|Exception" crash.log | head -10 || echo "(none)"

echo "=== Stopping the recorder and writing the HAR ==="
kill $PROXY_PID || true
sleep 3
HAR_OUT=dump.har mitmdump -r dump.mitm -s har_dump.py -q || true
ls -la dump.har dump.mitm firebase.log crash.log screen-*.png ui-fail-*.xml || true
