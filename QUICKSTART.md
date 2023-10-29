# Quick Start Guide

## Important: PKG vs DMG

**For end users installing Homebridge:**
- Use the `.pkg` installer - this installs the full Homebridge service
- The `.dmg` only contains launcher apps and requires the service to be installed first

**For developers:**
- Use `./build-local.sh` to build both formats

## Build locally (one command)

```bash
./build-local.sh
```

This will automatically:
1. Prepare staging payload with Node.js binaries
2. Build .pkg (if Packages app is installed)
3. Create .dmg with your app bundles

**Outputs** (in `build/` directory):
- `homebridge-staging.tar.gz` - staging payload
- `homebridge.pkg` - installer package (if built)
- `homebridge.dmg` - disk image with apps

## Quick builds

### Just want the DMG?
```bash
./build-local.sh --dmg-only
```

### Or use Makefile targets:
```bash
make local          # Full build
make dmg            # Just DMG
make staging        # Just staging
make pkg            # Just .pkg
```

## Sign the apps in DMG

```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" bash scripts/make-dmg.sh
```

## GitHub Actions

Push to `main` or `beta` branch and the workflow will:
- Build staging on Linux (via Docker)
- Build .pkg and .dmg on macOS runner
- Upload artifacts

See `.github/workflows/build.yml` for the full workflow.

To enable signing/notarization in CI, uncomment the `sign-and-notarize` job and add these secrets:
- `APPLE_CERTIFICATE_P12` - base64 encoded p12 certificate
- `APPLE_CERTIFICATE_PASSWORD` - certificate password
- `APPLE_ID` - your Apple ID
- `APPLE_APP_PASSWORD` - app-specific password
- `APPLE_TEAM_ID` - your team ID
- `APPLE_SIGN_ID` - signing identity name

## Troubleshooting

**"packagesbuild not found"**
- Install [Packages app](http://s.sudre.free.fr/Software/Packages/about.html)
- Or run: `brew install --cask packages`

**"hdiutil not found"**
- DMG creation only works on macOS

**Want to customize the build?**
- Set `NODE_VERSION` env var to pin a specific Node version
- Set `VOL_NAME` to customize DMG volume name
- Set `DMG_NAME` to customize DMG filename
