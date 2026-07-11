# Packaging & Release

## One-time setup
1. **Notary credentials** — store a keychain profile named `CCTT-notary`:
   ```
   xcrun notarytool store-credentials "CCTT-notary" \
     --apple-id "<your-apple-id>" --team-id 9WFDLY652Y --password "<app-specific-password>"
   ```
2. **Sparkle EdDSA key** — generate once; the private key is stored in your
   login Keychain, the public key is printed:
   ```
   $(find .build -name generate_keys -type f | head -1)
   ```
   Copy the printed public key and export it when packaging:
   ```
   export CCTT_ED_PUBKEY="<printed public key>"
   ```

## Per release
```
export CCTT_ED_PUBKEY="<public key>"
packaging/package_app.sh <version>
packaging/release.sh <version>
gh release create v<version> build/CCTT-<version>.zip --title "CCTT v<version>" --notes "…"
git add appcast.xml && git commit -m "release: v<version>" && git push
```
The feed lives at `https://raw.githubusercontent.com/Arc86/CCTT/main/appcast.xml`;
enclosure zips are GitHub Release assets.

## App icon

The Finder/Dock icon (`AppIcon.icns`, referenced by `CFBundleIconFile` and copied
into the bundle by `package_app.sh`) plus the runtime Dock PNG are generated from
`packaging/icon/CCTT-logo-source.png`. Regenerate after changing the logo:

```sh
packaging/icon/make_icon.sh
```
Both `packaging/icon/AppIcon.icns` and the `AppIcon-1024.png` copies are committed
so releases don't need Python/PIL at package time.
