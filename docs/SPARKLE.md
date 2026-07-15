# Sparkle auto-update

codexisland4custom ships with [Sparkle 2](https://sparkle-project.org). On launch and on a daily cadence the app can fetch the appcast attached to the latest GitHub Release, compare versions, and prompt the user to download + install if a newer build is listed.

The default feed URL is:

```text
https://github.com/shawn9960206-dotcom/codexisland4custom/releases/latest/download/appcast.xml
```

## One-time maintainer setup

1. Vendor Sparkle:

   ```sh
   ./scripts/setup-sparkle.sh
   ```

2. Generate the EdDSA keypair:

   ```sh
   ./Vendor/Sparkle/bin/generate_keys
   ```

3. Put the public key in `build.sh` as `SU_PUBLIC_KEY`.

4. Export the private key for CI use:

   ```sh
   ./Vendor/Sparkle/bin/generate_keys -x sparkle_ed_priv
   ```

5. Add the private key content to this repository's GitHub Actions secret:

   ```text
   SPARKLE_ED_PRIVATE_KEY
   ```

Never commit the private key.

## Cutting a release

1. Bump `VERSION`.
2. Commit, tag, and push:

   ```sh
   git commit -am "chore(release): bump VERSION to X.Y.Z"
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

3. The release workflow builds the DMG, signs the appcast, and uploads both to GitHub Releases.

## Local dry-run

```sh
./release.sh
```

The DMG and appcast are generated under `dist/`.

## Disabling update checks for a build

Set `SU_FEED_URL=` before running `build.sh`.
