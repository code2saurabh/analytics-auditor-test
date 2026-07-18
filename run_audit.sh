#!/usr/bin/env bash
set -x

# ============================================================================
#  Screen-reading tapper.
#  Instead of tapping random pixels, we ask Android for a dump of everything
#  on screen (text + coordinates), find the element whose text matches what we
#  want, and tap the centre of its box. This works on any screen size and any
#  app, because it finds things by their words, not by fixed pixels.
# ============================================================================

# tap_text "some words"  -> finds an element containing those words, taps it.
# Returns 0 if it tapped something, 1 if it found nothing.
tap_text() {
  local want="$1"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
  # Find the first node whose text= or content-desc= contains $want (case-insensitive),
  # and read its bounds="[x1,y1][x2,y2]". Then tap the centre.
  local coords
  coords=$(python3 - "$want" <<'PYE'
import sys, re, unicodedata
def flat(t):
    # strip accents so "Akceptuje" matches "Akceptuje" with a tail, etc.
    t = unicodedata.normalize('NFKD', t)
    return ''.join(c for c in t if not unicodedata.combining(c)).lower()
want = flat(sys.argv[1])
try:
    xml = open('/tmp/ui.xml', encoding='utf-8').read()
except Exception:
    print(""); sys.exit()
for m in re.finditer(r'<node[^>]*?>', xml):
    tag = m.group(0)
    tm = re.search(r'text="([^"]*)"', tag)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    hay = flat((tm.group(1) if tm else "") + " " + (dm.group(1) if dm else ""))
    if want in hay and hay.strip():
        bm = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if bm:
            x1,y1,x2,y2 = map(int, bm.groups())
            print(f"{(x1+x2)//2} {(y1+y2)//2}")
            break
PYE
)
  if [ -n "$coords" ]; then
    echo "TAP  '$want'  at  $coords"
    adb shell input tap $coords
    return 0
  else
    echo "SKIP '$want'  (not found on screen)"
    return 1
  fi
}

# type_text "words"  -> types into whatever field is focused.
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
  # An .apkm / .xapk / .apks bundle is a zip CONTAINING .apk files.
  # A plain .apk is also a zip, but has no .apk files inside it. That is the test.
  if unzip -l "$TARGET" | grep -q "\.apk\s*$"; then
    echo "Bundle detected - unpacking split APKs"
    mkdir -p /tmp/splits && unzip -o -q "$TARGET" -d /tmp/splits
    echo "--- splits found ---"
    ls -la /tmp/splits/*.apk
    echo "--- installing all splits together ---"
    adb install-multiple -r /tmp/splits/*.apk || INSTALL_OK=0
  else
    echo "Single APK detected"
    adb install -r "$TARGET" || INSTALL_OK=0
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
# -3 lists only user-installed apps, so we ignore everything Google ships.
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
# Harmless if the app does not use Firebase.
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
# JOURNEY_STEPS comes in from the workflow as one instruction per line.
# Each line is either:   tap Some Text       (find that text on screen, tap it)
#                        type some words     (type into the focused field)
#                        wait 3              (pause N seconds)
#                        key back            (press a hardware key)
# If no steps were supplied, fall back to just dismissing a consent dialog.
STEP_NUM=0
run_step() {
  local verb="$1"; shift
  local arg="$*"
  case "$verb" in
    tap)  tap_text "$arg" || true ;;
    type) type_text "$arg" ;;
    wait) sleep "${arg:-2}" ;;
    key)  adb shell input keyevent "KEYCODE_$(echo "$arg" | tr a-z A-Z)" ;;
    *)    echo "unknown step: $verb $arg" ;;
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
  echo "No journey supplied - just trying to dismiss a consent dialog."
  for word in Accept Akceptuje Agree Zgadzam Allow OK Continue Got; do
    tap_text "$word" && break
  done
fi

sleep 5
adb exec-out screencap -p > screen-2-after-journey.png

echo "=== Backgrounding, then leaving the SDK alone to flush ==="
adb shell input keyevent KEYCODE_HOME
sleep 60

echo "=== Logs ==="
adb logcat -d -s FA:V FA-SVC:V > firebase.log 2>&1 || true
adb logcat -d -s AndroidRuntime:E ActivityManager:E > crash.log 2>&1 || true
echo "--- last 20 lines of Firebase log ---"
tail -20 firebase.log || true
echo "--- any crashes ---"
grep -iE "FATAL|Exception" crash.log | head -10 || echo "(none)"

echo "=== Stopping the recorder and writing the HAR ==="
kill $PROXY_PID || true
sleep 3
HAR_OUT=dump.har mitmdump -r dump.mitm -s har_dump.py -q || true
ls -la dump.har dump.mitm firebase.log crash.log screen-*.png || true
