#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$package_dir/../.." && pwd)"
cd "$package_dir"

cmake -S "$repo_dir" -B "$repo_dir/build/nox" -G Ninja \
    -DGUI=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)" \
    -DQT_NO_PRIVATE_MODULE_WARNING=ON
cmake --build "$repo_dir/build/nox" -j 8

swift build -c release

app_dir="$package_dir/build/qBitX.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$package_dir/.build/release/qBitX" "$app_dir/Contents/MacOS/qBitX"
mkdir -p "$app_dir/Contents/Resources"
cp "$repo_dir/dist/mac/qbittorrent_mac.icns" "$app_dir/Contents/Resources/qBitX.icns"

helper_dir="$app_dir/Contents/Helpers/qbittorrent-nox.app"
mkdir -p "$app_dir/Contents/Helpers"
if [ -d "$helper_dir" ]; then
    backup_dir="$(mktemp -d "$package_dir/build/helper-backup.XXXXXX")"
    mv "$helper_dir" "$backup_dir/"
fi
ditto "$repo_dir/build/nox/qbittorrent-nox.app" "$helper_dir"
qt_plugins="$(brew --prefix qtbase)/share/qt/plugins"
mkdir -p "$helper_dir/Contents/PlugIns/tls" "$helper_dir/Contents/PlugIns/sqldrivers"
cp "$qt_plugins/tls/libqopensslbackend.dylib" "$helper_dir/Contents/PlugIns/tls/"
cp "$qt_plugins/sqldrivers/libqsqlite.dylib" "$helper_dir/Contents/PlugIns/sqldrivers/"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>qBitX</string>
    <key>CFBundleIdentifier</key>
    <string>life.andreacodin.qbitx.preview</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>qBitX</string>
    <key>CFBundleIconFile</key>
    <string>qBitX.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>qBitX uses macOS system events to perform a power action you selected after downloads complete.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "$app_dir"
