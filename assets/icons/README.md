# Homebridge App Icons

This directory contains the official Homebridge branding assets used for the macOS app icon.

## Source

Icons are sourced from the official [Homebridge Branding Repository](https://github.com/homebridge/branding).

## Files

- `homebridge-color-square.png` - Official color square logo (PNG)
- `homebridge-color-round.png` - Official color round logo (PNG)
- `Homebridge.icns` - macOS app icon bundle (generated from square PNG)

## Icon Generation

The `.icns` file is generated using macOS `iconutil`:

```bash
# Create iconset with all required sizes
mkdir -p homebridge.iconset
sips -z 16 16 homebridge-color-square.png --out homebridge.iconset/icon_16x16.png
sips -z 32 32 homebridge-color-square.png --out homebridge.iconset/icon_16x16@2x.png
sips -z 32 32 homebridge-color-square.png --out homebridge.iconset/icon_32x32.png
sips -z 64 64 homebridge-color-square.png --out homebridge.iconset/icon_32x32@2x.png
sips -z 128 128 homebridge-color-square.png --out homebridge.iconset/icon_128x128.png
sips -z 256 256 homebridge-color-square.png --out homebridge.iconset/icon_128x128@2x.png
sips -z 256 256 homebridge-color-square.png --out homebridge.iconset/icon_256x256.png
sips -z 512 512 homebridge-color-square.png --out homebridge.iconset/icon_256x256@2x.png
sips -z 512 512 homebridge-color-square.png --out homebridge.iconset/icon_512x512.png
cp homebridge-color-square.png homebridge.iconset/icon_512x512@2x.png

# Generate .icns
iconutil -c icns homebridge.iconset -o Homebridge.icns
```

## License

Homebridge logos are used in accordance with the [Homebridge Branding Guidelines](https://github.com/homebridge/branding#logo-usage).

Logo design credit: [Gabriel Garcia](https://github.com/ggabogarcia)
