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
gh release create v<version> build/CCTTApp-<version>.zip --title "CCTT v<version>" --notes "…"
git add appcast.xml && git commit -m "release: v<version>" && git push
```
The feed lives at `https://raw.githubusercontent.com/Arc86/CCTT/main/appcast.xml`;
enclosure zips are GitHub Release assets.
