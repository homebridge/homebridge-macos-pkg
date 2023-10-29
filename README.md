# Homebridge for macOS - Standalone Edition

**No installation required!** Just drag and drop. 🎉

This project builds a **self-contained Homebridge.app** that works on all modern macOS versions, including Sequoia (macOS 26+), without requiring system installation or admin privileges.

## Quick Start

```bash
./build-local.sh
```

Output: `build/homebridge-standalone-2.0.0.dmg` (~50 MB)

## For End Users

### Installation
1. Download the DMG
2. Open it and drag Homebridge.app to Applications
3. Launch the app
4. On first run, it installs Homebridge automatically (~1 minute)
5. Web interface opens at http://localhost:8581

### Features
✅ No system installation required  
✅ No sudo/admin privileges needed  
✅ Works on macOS 10.14+ (including latest versions)  
✅ Bundles Node.js v20 LTS runtime  
✅ Stores data in ~/Library/Application Support/Homebridge  
✅ Clean uninstall: just delete the app and data folder  

### How It Works

**First Launch:**
The app will:
1. Create `~/Library/Application Support/Homebridge`
2. Install `homebridge` and `homebridge-config-ui-x` using npm
3. Start the Homebridge service
4. Open your browser to the web interface

**Subsequent Launches:**
- If Homebridge is already running, just opens the web interface
- If not running, starts it and opens the interface

### Data Location
All data is stored in: `~/Library/Application Support/Homebridge`
- Configuration files
- Plugins
- Logs
- Node modules

### Uninstall
1. Delete Homebridge.app
2. Delete ~/Library/Application Support/Homebridge

That's it! No system files to clean up.

## For Developers

### Build Commands

**Standalone app (recommended):**
```bash
./build-local.sh
# Creates: build/homebridge-standalone-2.0.0.dmg
```

**Legacy PKG (system installation):**
```bash
./build-local.sh legacy
# ⚠️ May not work on macOS Sequoia+ due to security restrictions
```

### Test the App
```bash
# Run directly
open build/Standalone/Homebridge.app

# Or open the DMG
open build/homebridge-standalone-*.dmg
```

### Sign for Distribution
```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/make-standalone-dmg.sh
```

### Notarization
```bash
# Sign
SIGN_ID="Developer ID Application: Your Name" bash scripts/make-standalone-dmg.sh

# Notarize
xcrun notarytool submit build/homebridge-standalone-2.0.0.dmg \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAMID" \
  --wait

# Staple
xcrun stapler staple build/homebridge-standalone-2.0.0.dmg
```

### Troubleshooting

**App won't open:**
- Check Console.app for errors
- Right-click → Open (for unsigned builds)

**Installation fails on first launch:**
- Check network connection (needs to download packages)
- Check `~/Library/Application Support/Homebridge/homebridge.log`
- Force reinstall: Delete `~/Library/Application Support/Homebridge/node_modules` and `.node-version`, then relaunch

**Port already in use:**
- Another instance might be running: `lsof -ti:8581`
- Kill it: `kill $(lsof -ti:8581)`

**Module not found errors (node-pty, systeminformation, etc.):**
- This happens if installation was interrupted or corrupt
- Delete `~/Library/Application Support/Homebridge/node_modules` and `.node-version`
- Relaunch the app to trigger a clean reinstall

**Node version compatibility:**
- The app bundles Node.js v20 LTS by default for maximum plugin compatibility
- To use a different Node version, set `NODE_VERSION` before building:
  ```bash
  NODE_VERSION=v22.11.0 ./build-standalone-app.sh
  ```

## Architecture

### App Bundle Structure
```
Homebridge.app/
├── Contents/
│   ├── Info.plist          # App metadata
│   ├── PkgInfo             # Package type
│   ├── MacOS/
│   │   └── Homebridge      # Launcher script
│   ├── Frameworks/
│   │   └── node/           # Bundled Node.js runtime
│   │       ├── bin/
│   │       └── lib/
│   └── Resources/
│       └── AppIcon.icns    # App icon
```

### Runtime Flow
1. User launches `Homebridge.app`
2. Launcher script (`Contents/MacOS/Homebridge`):
   - Sets up PATH to bundled Node.js v20 LTS
   - Creates user data directory
   - Checks if Homebridge is installed (and Node version matches)
   - Installs/reinstalls on first run or Node version change using npm
   - Starts `homebridge-config-ui-x` in standalone mode
   - Opens web browser to UI

### User Data Directory
```
~/Library/Application Support/Homebridge/
├── node_modules/           # Homebridge + plugins
│   ├── homebridge/
│   └── homebridge-config-ui-x/
├── package.json            # Dependencies
├── config.json             # Homebridge config
└── homebridge.log          # Log file
```

### What's Different?

**Standalone (NEW):**
- Self-contained app bundle
- No system files
- No LaunchDaemon
- Runs in user space
- Works on all modern macOS

**Legacy PKG (OLD):**
- System installation to /Library
- Requires admin privileges
- LaunchDaemon service
- ❌ Blocked on macOS Sequoia+

### Why Standalone?

Modern macOS versions have strict **System Volume protections**. Installing to `/Library` or creating system LaunchDaemons requires:
- Full Disk Access approval
- Signed installer with proper entitlements
- Often still fails on latest macOS

The standalone approach sidesteps all of this by keeping everything in user space.

## Documentation

- [QUICKSTART.md](QUICKSTART.md) - Legacy PKG quick start

## GitHub Actions

See `.github/workflows/build.yml` for CI/CD that builds:
- Standalone DMG (macOS runner)
- Legacy PKG (macOS runner)
- Staging tarball (Linux container)

## Changelog

- feat: terminal session persistence and macOS shell optimization
  - Enables the Homebridge UI Terminal by default and improves PATH so `hb-service` resolves to the bundled shim
  - Improves macOS shell environment startup for more reliable commands and session persistence in the UI Terminal
  - Action: restart the Homebridge app/service once to apply; then open UI → Tools → Terminal and you can run `hb-service update-node`

- chore: update npm pack
  - Updates packaging to use `npm pack` for more predictable, smaller artifacts and correct file inclusion/exclusion
  - Action: no user action required; build outputs are more reproducible

## License

Copyright (C) 2022-2025 Homebridge

Originally developed by oznu.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [GNU General Public License](./LICENSE) for more details.
