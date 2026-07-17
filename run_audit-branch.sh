#!/usr/bin/env bash
set -x

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

echo "=== A crude journey: 30 random taps ==="
# Not a real journey - just enough poking to make a real app do something.
# Fixed seed so the same walk repeats. Nav/system keys off so it does not
# just press Back and quit.
adb shell monkey -p "$PKG" --throttle 800 --pct-syskeys 0 -s 42 -v 30 || true
sleep 10
adb exec-out screencap -p > screen-2-after-taps.png

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
