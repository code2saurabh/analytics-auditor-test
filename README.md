# Before uploading this to GitHub

This project is complete except for ONE file you already have: `google-services.json`
(the one you downloaded from the Firebase console).

Copy that file into this exact folder, right next to `build.gradle`:

    app/google-services.json

So the final structure should look like:

    app/
      build.gradle
      google-services.json   <-- add this one yourself
      src/...

Once that file is in place, upload this entire folder to a new GitHub repository
(drag-and-drop everything in), and the "Build APK" workflow under the Actions tab
will run automatically and produce a downloadable app-debug.apk.
