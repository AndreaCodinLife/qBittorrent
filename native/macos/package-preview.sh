#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$package_dir/../.." && pwd)"
cd "$package_dir"

cmake -S "$repo_dir" -B "$repo_dir/build/nox" -G Ninja \
    -DGUI=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)" \
    -DQT_NO_PRIVATE_MODULE_WARNING=ON
cmake --build "$repo_dir/build/nox" -j 8

swift build -c release --product qBitX
swift build -c release --product qBitXWidget

signing_identity="${QBITX_CODE_SIGN_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    account_name="$(id -un)"
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' -v user_name="$account_name" '/Apple Development:/ { if (fallback == "") fallback = $2; if (index(tolower($2), tolower(user_name)) > 0) chosen = $2 } END { if (chosen != "") print chosen; else print fallback }')"
fi
app_group_identifier=""
if [ -n "$signing_identity" ]; then
    team_identifier="$(security find-certificate -c "$signing_identity" -p 2>/dev/null | openssl x509 -noout -subject -nameopt RFC2253 | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p')"
    if [[ ! "$team_identifier" =~ ^[A-Z0-9]{10}$ ]]; then
        echo "Could not read the Team ID from QBITX_CODE_SIGN_IDENTITY '$signing_identity'." >&2
        exit 1
    fi
    app_group_identifier="${QBITX_APP_GROUP_IDENTIFIER:-${team_identifier}.qbitx.shared}"
    if [[ "$app_group_identifier" != "${team_identifier}."* ]]; then
        echo "QBITX_APP_GROUP_IDENTIFIER must begin with ${team_identifier}." >&2
        exit 1
    fi
fi

preview_root="${TMPDIR:-/tmp}/qbitx-preview-${UID}"
mkdir -p "$preview_root"
staging_root="$(mktemp -d "$preview_root/package.XXXXXX")"
app_dir="$staging_root/qBitX.app"
app_bundle_identifier="life.andreacodin.qbitx.preview"
mkdir -p "$app_dir/Contents/MacOS"
cp "$package_dir/.build/release/qBitX" "$app_dir/Contents/MacOS/qBitX"
mkdir -p "$app_dir/Contents/Resources"
cp "$repo_dir/dist/mac/qbittorrent_mac.icns" "$app_dir/Contents/Resources/qBitX.icns"

helper_dir="$app_dir/Contents/Helpers/qbittorrent-nox.app"
mkdir -p "$app_dir/Contents/Helpers"
ditto --norsrc --noextattr "$repo_dir/build/nox/qbittorrent-nox.app" "$helper_dir"
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
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array><string>torrent</string></array>
            <key>CFBundleTypeName</key>
            <string>BitTorrent Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>org.bittorrent.torrent</string></array>
        </dict>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleURLName</key>
            <string>BitTorrent Magnet URL</string>
            <key>CFBundleURLSchemes</key>
            <array><string>magnet</string></array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string><string>public.item</string></array>
            <key>UTTypeDescription</key>
            <string>BitTorrent Document</string>
            <key>UTTypeIdentifier</key>
            <string>org.bittorrent.torrent</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>torrent</string></array>
                <key>public.mime-type</key>
                <array><string>application/x-bittorrent</string></array>
            </dict>
        </dict>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>qBitX uses macOS system events to perform a power action you selected after downloads complete.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>qBitX uses your local network to discover peers for torrents you add.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [ -n "$app_group_identifier" ]; then
    /usr/libexec/PlistBuddy -c "Add :QBitXAppGroupIdentifier string $app_group_identifier" "$app_dir/Contents/Info.plist"

    widget_dir="$app_dir/Contents/PlugIns/qBitXWidget.appex"
    mkdir -p "$widget_dir/Contents/MacOS"
    cp "$package_dir/.build/release/qBitXWidget" "$widget_dir/Contents/MacOS/qBitXWidget"
    cat > "$widget_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>qBitXWidget</string>
    <key>CFBundleIdentifier</key>
    <string>${app_bundle_identifier}.widget</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>qBitXWidget</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>QBitXAppGroupIdentifier</key>
    <string>${app_group_identifier}</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

    cat > "$staging_root/qBitX-app.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array><string>${app_group_identifier}</string></array>
</dict>
</plist>
PLIST
    cat > "$staging_root/qBitX-widget.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array><string>${app_group_identifier}</string></array>
</dict>
</plist>
PLIST
fi

python3 "$package_dir/scripts/generate-translations.py" "$repo_dir" "$app_dir/Contents/Resources"

# The workspace may be hosted in a File Provider directory, which adds Finder
# metadata that codesign rejects on nested Qt bundles. This is a generated app
# bundle, so clear its filesystem metadata before making a local ad-hoc signature.
xattr -cr "$app_dir"
if [ -n "$app_group_identifier" ]; then
    codesign --force --deep --sign "$signing_identity" "$helper_dir"
    codesign --force --sign "$signing_identity" \
        --entitlements "$staging_root/qBitX-widget.entitlements" \
        --identifier "${app_bundle_identifier}.widget" "$widget_dir"
    codesign --force --sign "$signing_identity" \
        --entitlements "$staging_root/qBitX-app.entitlements" \
        --identifier "$app_bundle_identifier" "$app_dir"
else
    echo "No Apple Development identity was found; packaging this preview without the WidgetKit extension." >&2
    codesign --force --deep --sign - --identifier "$app_bundle_identifier" "$app_dir"
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"

output_app="$preview_root/qBitX.app"
if [ -e "$output_app" ]; then
    mv "$output_app" "$preview_root/qBitX.previous.$(date +%Y%m%d-%H%M%S).app"
fi
mv "$app_dir" "$output_app"
rm -f "$staging_root"/*.entitlements
rmdir "$staging_root"
echo "$output_app"
