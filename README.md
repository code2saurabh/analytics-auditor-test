# Analytics Auditor Test App

Minimal Android app used to prove the audit pipeline: build -> run on a real
device -> capture the GA4 / Firebase Analytics traffic it fires.

## THE ONE FILE YOU MUST ADD YOURSELF

This zip does NOT contain `google-services.json` (it is your private Firebase
config). Put your existing copy back at exactly:

```
app/google-services.json
```

Right next to `app/build.gradle`. The build will fail without it.

## How to build

Builds no longer start automatically on push. To build:

Actions tab -> "Build APK" in the left sidebar -> "Run workflow" button on the
right -> Run workflow. Wait for the green tick, then open the run and download
the `app-debug` artifact at the bottom.

## What changed vs the previous version

1. `AndroidManifest.xml` now declares `android.permission.INTERNET`.
   Without it Android blocks every network connection with no visible error.

2. `res/xml/network_security_config.xml` is new, and the manifest points at it.
   Android 7+ apps do not trust user-installed certificates by default.
   BrowserStack captures traffic using mitmproxy, whose certificate is installed
   as a user certificate. Without this file the app refuses the proxy and no
   network logs are ever produced. This is why Chrome captured fine (Chrome does
   trust user certificates) and this app captured nothing.

3. `MainActivity.kt` now fires two "canary" plain HTTPS requests alongside the
   Firebase event, and prints every result on screen.

   The canary separates two different questions in a single session:

   | Canary in HAR | app-measurement.com in HAR | Meaning                                |
   |---------------|----------------------------|----------------------------------------|
   | no            | no                         | permission / certificate still broken  |
   | yes           | no                         | capture works, Firebase is just batching |
   | yes           | yes                        | Milestone 2 done                       |

   Firebase batches events for roughly one hour before uploading unless debug
   mode is on, and debug mode on Android needs `adb shell setprop`, which
   App Live does not give you. So "no app-measurement.com" is expected and is
   NOT the same failure as before.

## BrowserStack session plan (order matters)

1. Upload `app-debug.apk` to App Live.
2. Pick an Android 12 or 13 device (Pixel is safest).
3. BEFORE launching the app: DevTools -> Network -> "Enable for all traffic"
   -> Save configuration. The device restarts automatically.
4. Now launch the app. Note the RUN ID shown at the top of the screen.
5. Read the canary lines in the on-screen log. That is your diagnosis.
6. Tap button 3 (25 events). Press Home. Wait ~60 seconds. Reopen. Home again.
7. DevTools -> Network -> filter by your RUN ID, then filter by `app-measurement`.
8. Download the HAR before the session expires.

### Reading the canary line

- `canary www.gstatic.com -> HTTP 204` : network + certificate + proxy all good.
- `FAILED -> SSLHandshakeException`    : certificate config not applied.
- `FAILED -> UnknownHostException`     : no network / permission problem.
- `FAILED -> SecurityException`        : INTERNET permission missing.
- `FIREBASE INIT FAILED`               : `google-services.json` not wired up.
