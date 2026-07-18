# Sparkle updates

Relay uses Sparkle 2 to install signed updates outside the Mac App Store. The
public EdDSA key is embedded in `Resources/Info.plist`; the private key remains
in the release owner's login Keychain as “Private key for signing Sparkle
updates.” Never commit or upload the private key.

## Prepare a release

1. Increment both `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Build the release archive:

   ```bash
   scripts/build-release-dmg.sh
   ```

3. Generate and sign the update feed:

   ```bash
   scripts/generate-appcast.sh
   ```

4. Commit the updated `appcast.xml`, tag the same version as `v<version>`, and
   upload `dist/Relay-macos-universal.dmg` to that GitHub release. The URL
   embedded in the feed is tag-specific even though the asset name stays
   stable.

The first signing operation may prompt for the login Keychain password. Choose
Always Allow if this is the trusted Sparkle tool from Swift Package Manager.
Back up the private signing key in a password manager or other encrypted store:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /secure/path/relay-sparkle-private-key
```

Treat that exported file like a password and remove any unencrypted temporary
copy after securing the backup.

## Manual upgrade test

Create a baseline app with build number 3 and an update with build number 4:

```bash
scripts/prepare-sparkle-test.sh
```

The script prints two commands. Run the local HTTP server first, then launch
the baseline app. Expand Relay after the automatic check finds version 1.0.3,
then click **Install & Relaunch** in the update banner. Relay should show its
download/preparation status, replace the baseline bundle, and relaunch it.
Verify the installed version afterward:

```bash
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  dist/sparkle-test/baseline/Relay.app/Contents/Info.plist
```

Expected output: `1.0.3`.

This local test uses loopback HTTP only. Production updates use the HTTPS feed
declared in `Resources/Info.plist`.
