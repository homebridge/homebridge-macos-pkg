#!/bin/sh

rm -rf build
rm -rf "Library/Application Support/Homebridge/node-x86_64"
rm -rf "Library/Application Support/Homebridge/node-arm64"

mkdir "Library/Application Support/Homebridge/node-x86_64"
mkdir "Library/Application Support/Homebridge/node-arm64"

NODE_VERSION="$(curl -s https://nodejs.org/dist/index.json | jq -r 'map(select(.lts))[0].version')"

if [ ! -f  "node-$NODE_VERSION-darwin-x64.tar.gz" ]; then
    curl -SLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-x64.tar.gz"
fi

if [ ! -f  "node-$NODE_VERSION-darwin-arm64.tar.gz" ]; then
    curl -SLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-arm64.tar.gz"
fi

tar xzf "node-$NODE_VERSION-darwin-x64.tar.gz" -C "Library/Application Support/Homebridge/node-x86_64/" --strip-components=1 --no-same-owner
tar xzf "node-$NODE_VERSION-darwin-arm64.tar.gz" -C "Library/Application Support/Homebridge/node-arm64/" --strip-components=1 --no-same-owner

packagesbuild --project homebridge.pkgproj
