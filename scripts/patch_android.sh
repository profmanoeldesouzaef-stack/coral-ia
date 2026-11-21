#!/usr/bin/env bash
# Ajusta o projeto Android gerado pelo `flutter create` às necessidades do app.
set -euo pipefail
G=android/app/build.gradle.kts
[ -f "$G" ] || G=android/app/build.gradle
sed -i -E 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 24/' "$G"
grep -qE 'minSdk(Version)?\s*=?\s*24' "$G" || { echo "minSdk 24 não aplicado em $G"; exit 1; }

M=android/app/src/main/AndroidManifest.xml
sed -i 's#<application#<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n    <application android:requestLegacyExternalStorage="true"#' "$M"
sed -i 's/android:label="coral_ia"/android:label="Coral IA"/' "$M"
grep -q RECORD_AUDIO "$M"
echo "Android ajustado: $G, $M"
