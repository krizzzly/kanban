#!/usr/bin/env bash
# Builds Kanban in release mode, assembles the .app bundle and signs it with the Apple
# Development identity (fallback: ad-hoc), then installs it to /Applications.
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

# ---------------------------------------------------------------------------
# Signierung
#
# Eine ad-hoc-Signatur hat keinen Team-Identifier. macOS bindet erteilte TCC-Rechte dann an den
# cdhash — und der ändert sich bei jedem Bau. Genau deshalb war Kanbans Benachrichtigungs-Erlaubnis
# nach jedem Rollout wieder weg. Mit einer echten Identität lautet die Anforderung „Bundle-Id +
# Zertifikat", und die überlebt den Neubau.
# ---------------------------------------------------------------------------
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development: c.hiller@iwf.ch (RVX4CBNYV9)}"
ENTITLEMENTS="$ROOT/Kanban.entitlements"

# Ablaufdatum des Zertifikats, leer wenn keines mit diesem Namen im Schlüsselbund liegt.
cert_expiry() {
  # `|| true`, damit `set -e` nicht zuschlägt, wenn gar kein solches Zertifikat da ist.
  security find-certificate -c "$1" -p 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true
}

# Signiert mit Zeitstempel. Ohne Netz ist der Zeitstempel-Dienst nicht erreichbar; dann wird
# hörbar ohne signiert, statt den Bau stehen zu lassen. Lokal ist das folgenlos — für eine
# spätere Notarisierung (Stufe 2) wäre der Zeitstempel Pflicht.
sign_with_timestamp() {
  local log
  if log="$(codesign --force --timestamp "$@" 2>&1)"; then
    [ -n "$log" ] && printf '%s\n' "$log"
    return 0
  fi
  if ! printf '%s' "$log" | grep -qi "timestamp"; then
    printf '%s\n' "$log" >&2
    return 1
  fi
  echo "!! Zeitstempel-Dienst nicht erreichbar (kein Netz?) — signiere ohne Zeitstempel."
  codesign --force --timestamp=none "$@"
}

# Fehlt die Identität (fremder Rechner, abgelaufenes Zertifikat), wird ad-hoc signiert statt
# abgebrochen: Der Bau soll überall durchlaufen, nur eben ohne den TCC-Gewinn.
# `find-identity -v` listet ausschliesslich gültige Identitäten — ein abgelaufenes Zertifikat
# fällt hier durch und bekommt darum sein Ablaufdatum genannt.
if [ "$CODESIGN_IDENTITY" != "-" ] \
   && ! security find-identity -v -p codesigning | grep -Fq "$CODESIGN_IDENTITY"; then
  echo "!! Signier-Identität nicht gültig im Schlüsselbund: $CODESIGN_IDENTITY"
  EXPIRY="$(cert_expiry "$CODESIGN_IDENTITY")"
  if [ -n "$EXPIRY" ]; then
    echo "!! Das Zertifikat liegt im Schlüsselbund, gilt aber nicht mehr (gültig bis: $EXPIRY)."
    echo "!! Erneuern: Xcode › Settings › Accounts › Manage Certificates › +"
  fi
  echo "!! Rückfall auf ad-hoc — die App läuft, verliert aber bei jedem Bau ihre TCC-Rechte."
  CODESIGN_IDENTITY="-"
fi

if [ "$CODESIGN_IDENTITY" = "-" ]; then
  echo "==> ad-hoc signing"
  codesign --force --sign - "$APP"
else
  EXPIRY="$(cert_expiry "$CODESIGN_IDENTITY")"
  echo "==> signing als $CODESIGN_IDENTITY${EXPIRY:+ (gültig bis $EXPIRY)}"
  # Von innen nach aussen signieren; `--deep` macht das Gegenteil und ist von Apple ausdrücklich
  # abgeraten. Die beiden Ordner, die SwiftPM ablegt (Kanban_Kanban.bundle,
  # SwiftTerm_SwiftTerm.bundle), sind reine Ressourcen-Ordner ohne Info.plist — codesign erkennt
  # sie nicht als Bundle („bundle format unrecognized") und die App-Signatur versiegelt sie
  # ohnehin als gewöhnliche Ressourcen. Die Schleife greift erst, wenn eine Abhängigkeit ein
  # echtes Bundle mitliefert.
  for b in "$APP/Contents/Resources"/*.bundle; do
    [ -f "$b/Contents/Info.plist" ] || continue
    echo "    - $(basename "$b")"
    sign_with_timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$b"
  done
  sign_with_timestamp --options runtime --entitlements "$ENTITLEMENTS" \
                      --sign "$CODESIGN_IDENTITY" "$APP"
fi

echo "==> Signatur prüfen"
if ! codesign --verify --strict --verbose=2 "$APP"; then
  echo "!! Signatur-Prüfung fehlgeschlagen. Das Bundle wird entfernt, statt eine kaputte App in"
  echo "!! /Applications stehen zu lassen — macOS würde sie beim Start ohnehin abweisen."
  rm -rf "$APP"
  exit 1
fi
codesign -dv --verbose=4 "$APP" 2>&1 \
  | grep -E '^(Identifier|Authority|Timestamp|TeamIdentifier|Signature)=|^CodeDirectory' || true

# spctl beurteilt die Weitergabe, nicht die Signatur: Mit einem Entwicklungs-Zertifikat ist
# „rejected" der erwartete Befund; erst Developer ID + Notarisierung ändern das. Darum Auskunft
# statt Abbruch.
echo '==> spctl (Auskunft — „rejected“ ist ohne Notarisierung erwartet)'
spctl -a -vvv -t exec "$APP" 2>&1 || true

# ---------------------------------------------------------------------------
# Stufe 2 — Notarisierung (schläft, bis ein Developer-ID-Zertifikat da ist)
#
# Greift nur, wenn tatsächlich mit einem „Developer ID Application"-Zertifikat signiert wurde.
# Mit dem Entwicklungs-Zertifikat von heute passiert hier nichts: Apple notarisiert nur
# Developer-ID-Signaturen. Voraussetzung ist ausserdem ein notarytool-Profil im Schlüsselbund:
#   xcrun notarytool store-credentials kanban-notary \
#     --apple-id <apple-id> --team-id <team-id> --password <app-spezifisches Passwort>
# Das Profil gehört in den Schlüsselbund, nicht ins Repo.
# ---------------------------------------------------------------------------
NOTARY_PROFILE="${NOTARY_PROFILE:-kanban-notary}"

case "$CODESIGN_IDENTITY" in
  "Developer ID Application"*)
    echo "==> Notarisierung (Profil: $NOTARY_PROFILE)"
    ZIPDIR="$(mktemp -d)"
    # `ditto -c -k --keepParent` ist der von Apple vorgeschriebene Weg; `zip` verliert die
    # Symlinks und Metadaten des Bundles.
    ditto -c -k --keepParent "$APP" "$ZIPDIR/Kanban.zip"
    if xcrun notarytool submit "$ZIPDIR/Kanban.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
       && xcrun stapler staple "$APP"; then
      echo "==> notarisiert und geheftet"
      # Jetzt muss spctl „accepted / source=Notarized Developer ID" sagen.
      spctl -a -vvv -t exec "$APP" 2>&1 || true
    else
      echo "!! Notarisierung fehlgeschlagen. Die App in /Applications ist signiert und läuft hier,"
      echo "!! taugt aber nicht zur Weitergabe."
      echo "!! Grund nachlesen: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
      echo "!! Profil fehlt? xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <team> --password <app-pw>"
    fi
    rm -rf "$ZIPDIR"
    ;;
  *)
    # Entwicklungs-Zertifikat oder ad-hoc: nicht notarisierbar. Warum, steht in CLAUDE.md
    # unter „Signierung".
    :
    ;;
esac

# Launch Services die neue Info.plist unterschieben: ohne das kennt der Finder die
# Markdown-Zuordnung erst nach einem Neustart (oder gar nicht, wenn der alte Eintrag noch steht).
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" || true

echo "==> done: $APP"
