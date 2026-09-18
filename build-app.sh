#!/usr/bin/env bash
# Builds Kanban in release mode and assembles a launchable, ad-hoc-signed .app bundle in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)"
# Install straight into /Applications — that's where the app is launched from and the path macOS
# has registered for notifications under bundle id ch.iwf.kanban. Building into dist/ left a second
# stale bundle with the same id, which confused Launch Services / notifications.
APP="/Applications/Kanban.app"

echo "==> assembling $APP"
rm -rf "$APP"
rm -rf "$ROOT/dist/Kanban.app"   # drop the old duplicate bundle (same id → routing confusion)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Kanban" "$APP/Contents/MacOS/Kanban"

# Bundle any resource bundles the dependencies ship (e.g. SwiftTerm's Metal shader).
for b in "$BIN"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# App icon (generated from hermes/extension/icons/icon.svg via make-icon.sh).
[ -f "$ROOT/AppIcon.icns" ] && cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kanban</string>
    <key>CFBundleDisplayName</key><string>Kanban</string>
    <key>CFBundleIdentifier</key><string>ch.iwf.kanban</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>Kanban</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>

    <!-- Markdown-Dateien öffnen (Finder: „Öffnen mit › Kanban"). Rolle ist bewusst `Viewer`
         und Rang `Alternate`: Kanban zeigt die Datei, bearbeitet sie nicht, und soll dem
         Editor die Standard-Zuordnung für .md nicht wegnehmen. -->
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key><string>Markdown</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array><string>net.daringfireball.markdown</string></array>
        <key>CFBundleTypeExtensions</key>
        <array><string>md</string><string>markdown</string><string>mdown</string></array>
      </dict>
    </array>

    <!-- Der Typ gehört nicht uns (Daring Fireball hat ihn geprägt, mehrere Apps deklarieren ihn),
         deshalb `imported` statt `exported`. Ohne die Deklaration kennt eine Maschine, auf der
         keine andere Markdown-App installiert ist, den Typ nicht — und „Öffnen mit" bliebe leer. -->
    <key>UTImportedTypeDeclarations</key>
    <array>
      <dict>
        <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
        <key>UTTypeDescription</key><string>Markdown</string>
        <key>UTTypeConformsTo</key>
        <array><string>public.plain-text</string></array>
        <key>UTTypeTagSpecification</key>
        <dict>
          <key>public.filename-extension</key>
          <array><string>md</string><string>markdown</string><string>mdown</string></array>
        </dict>
      </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APP"

# Launch Services die neue Info.plist unterschieben: ohne das kennt der Finder die
# Markdown-Zuordnung erst nach einem Neustart (oder gar nicht, wenn der alte Eintrag noch steht).
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" || true

echo "==> done: $APP"
