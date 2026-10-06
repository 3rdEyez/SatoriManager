# Existing-install APK signing compatibility

The latest locally validated `0.2.7+9` ARM64 APK is **unsigned**. Its package is
`com.example.satori_manager`, versionCode `9`. It cannot be installed directly.
`flutter_app/android/app/build.gradle.kts` currently assigns the release build
to the template's `debug` signing configuration. That source setting is not
proof that an output was signed: the actual APK fails `apksigner verify` with
`Missing META-INF/MANIFEST.MF`. Do not describe the current deliverable as a
signed development release, or run a build that implicitly creates a new key.

An in-place update requires the signing identity compatible with the installed
App. A freshly generated key with the same filename/alias does not recreate
that identity. The minimal approach keeps this package ID and uses the **original
App signing channel and existing key**, including the original debug keystore
if that is how the installed App was signed. Do not confuse the firmware RSA
OTA key with an Android App signing key. See the primary
[Android app signing documentation](https://developer.android.com/studio/publish/app-signing).

## Minimal preparation and later approved actions

1. Obtain an existing signed APK from the installation source, or (only after
   phone access is approved) read the installed package path/version and pull
   its APK for public certificate inspection. Do not uninstall or inspect App
   private data. This phase did not access the phone or run ADB.
2. Run `apksigner verify --print-certs` on that baseline APK to obtain its public
   certificate SHA256. Confirm package ID and installed versionCode. This needs
   no keystore/private key; no claim is made that these are already known.
3. Have the original signing channel use its existing key to sign the new APK.
   Android Studio's signed APK workflow can select an existing keystore rather
   than "Create new". If signing a prepared APK with apksigner, alignment must
   happen before signing. Enter any signing passwords privately in the signing
   tool; never put them in chat, logs, tracked `key.properties`, or shell argv.
   Do not read, export, regenerate or rotate key material as part of this prep.
4. Verify the resulting APK with apksigner and compare its signer with the
   installed baseline. Keep package ID equal, and use a versionCode above the
   installed version (9 is only usable if it satisfies that condition). Preserve
   local unsigned artifacts, report the new signed artifact's SHA, and never
   mistake source `signingConfig` for verification.
5. Only after explicit installation approval, perform a normal in-place update
   with the matched signing identity. If the key/channel is unavailable or the
   certificate differs, stop and report; do not silently uninstall, replace the
   App identity, downgrade or create another debug key.

The current signing config and old README wording alone cannot establish which
key signed the phone's installed App. This is the remaining compatibility fact,
not a reason to request Wi-Fi passwords or change the network. No private key
was read or used, no credential was created and no APK was installed here.
