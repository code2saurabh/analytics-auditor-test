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
echo "System certificates on device:"
adb shell "ls /system/etc/security/cacerts/ | wc -l"

echo "=== Firebase debug mode ==="
adb shell setprop debug.firebase.analytics.app com.example.analyticsauditor
adb shell setprop log.tag.FA VERBOSE
adb shell setprop log.tag.FA-SVC VERBOSE
adb shell getprop debug.firebase.analytics.app

echo "=== Starting the recorder ==="
HAR_OUT=dump.har mitmdump -w dump.mitm -s har_dump.py > mitm.log 2>&1 &
PROXY_PID=$!
sleep 5

echo "=== Installing and launching ==="
adb logcat -c
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell monkey -p com.example.analyticsauditor -c android.intent.category.LAUNCHER 1

# --- UPDATED: Increased sleep timers and removed the second monkey launch ---
echo "=== Letting the app fire, then letting Firebase flush ==="
sleep 45
adb shell input keyevent KEYCODE_HOME
echo "=== App backgrounded. Now leave the SDK completely alone. ==="
sleep 90

echo "=== What the Firebase SDK says it did ==="
adb logcat -d -s FA:V FA-SVC:V > firebase.log 2>&1 || true
tail -40 firebase.log || true

# --- ADDED: Logcat verification check right before killing the proxy ---
echo "=== Did the upload actually go? ==="
adb logcat -d -s FA:V FA-SVC:V | grep -iE "Uploading|upload_url|Successful upload|Network upload" | tail -20

echo "=== Stopping the recorder and writing the HAR ==="
kill $PROXY_PID || true
sleep 3
HAR_OUT=dump.har mitmdump -r dump.mitm -s har_dump.py -q || true
ls -la dump.har dump.mitm firebase.log || true
