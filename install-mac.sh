#!/bin/bash
# Dr. Claude installer for Mac. Run it by pasting this one line into Terminal:
#   curl -fsSL https://raw.githubusercontent.com/Blondeylocks/dr-claude-updates/main/install-mac.sh | bash
# What it does (no admin password needed):
#   ~/Library/Application Support/Dr Claude/python   its own Python 3.12 (python-build-standalone, checked by sha256)
#   ~/Library/Application Support/Dr Claude/app      the newest Dr. Claude (checked by sha256)
#   ~/Applications/Dr. Claude.app  + a Desktop shortcut
# Your classes go in Documents/Dr. Claude. Running it again updates/repairs and keeps your data.
set -euo pipefail

ROOT="$HOME/Library/Application Support/Dr Claude"
REPO="https://raw.githubusercontent.com/Blondeylocks/dr-claude-updates/main"
PY_TAG="20261110"
PY_VER="3.12.16"
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mSetup stopped: %s\033[0m\n%s\n\n' "$1" "Check your internet and paste the line again. Still stuck? Send a screenshot of this window to the person who sent you Dr. Claude."; exit 1; }
trap 'fail "something went wrong on line $LINENO."' ERR

printf '\n\033[1m🎓 Installing Dr. Claude, your study professor. This takes about 2 minutes.\033[0m\n'

case "$(uname -m)" in
  arm64)  ARCH="aarch64"; PY_SHA="e956e60bc9465d577ef8062059aa05cd3a2665b4b8678a2ed24e432368330b8f" ;;
  x86_64) ARCH="x86_64";  PY_SHA="83f2922437e6d546d0fcdb8c11f150a8e52787e8d9ea8651b1974e20908eb1bc" ;;
  *) fail "this Mac's chip ($(uname -m)) isn't supported." ;;
esac

mkdir -p "$ROOT"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# 1. Python (skipped if already there)
if [ ! -x "$ROOT/python/bin/python3" ]; then
  say "Getting Python (about 25 MB)…"
  PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/cpython-${PY_VER}%2B${PY_TAG}-${ARCH}-apple-darwin-install_only.tar.gz"
  curl -fL --progress-bar "$PY_URL" -o "$TMP/python.tgz" || fail "couldn't download Python."
  echo "$PY_SHA  $TMP/python.tgz" | shasum -a 256 -c - >/dev/null || fail "the Python download didn't match its fingerprint."
  rm -rf "$ROOT/python"
  tar -xzf "$TMP/python.tgz" -C "$ROOT"
fi
PY="$ROOT/python/bin/python3"
"$PY" -c "import ssl, sqlite3" || fail "Python didn't start."

# 2. The newest Dr. Claude (same files Windows gets)
say "Getting the newest Dr. Claude…"
curl -fsSL "$REPO/manifest.json" -o "$TMP/manifest.json" || fail "couldn't reach the Dr. Claude download."
"$PY" - "$TMP" <<'PYEOF'
import hashlib, json, sys, urllib.request, zipfile, shutil, os
tmp = sys.argv[1]
m = json.load(open(os.path.join(tmp, "manifest.json")))
zp = os.path.join(tmp, "app.zip")
req = urllib.request.Request(m["zip_url"], headers={"User-Agent": "Dr-Claude-mac-setup"})
with urllib.request.urlopen(req, timeout=300) as r, open(zp, "wb") as f:
    shutil.copyfileobj(r, f)
h = hashlib.sha256(open(zp, "rb").read()).hexdigest()
if h != m["sha256"]:
    sys.exit("The Dr. Claude download didn't match its fingerprint.")
out = os.path.join(tmp, "app")
zipfile.ZipFile(zp).extractall(out)
print("   version", m["version"])
PYEOF
mkdir -p "$ROOT/app"
# replace the app files but keep anything the app saved inside its folder
find "$ROOT/app" -mindepth 1 -maxdepth 1 ! -name data -exec rm -rf {} +
cp -R "$TMP/app/." "$ROOT/app/"

# 3. A real Mac app to open it with
say "Adding Dr. Claude to your Applications…"
APPB="$HOME/Applications/Dr. Claude.app"
rm -rf "$APPB"
mkdir -p "$APPB/Contents/MacOS" "$APPB/Contents/Resources"
cat > "$APPB/Contents/MacOS/Dr Claude" <<LAUNCH
#!/bin/bash
cd "$ROOT/app"
exec "$PY" "$ROOT/app/dr_claude.py" >>"$ROOT/launch.log" 2>&1
LAUNCH
chmod +x "$APPB/Contents/MacOS/Dr Claude"
cat > "$APPB/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Dr. Claude</string>
  <key>CFBundleDisplayName</key><string>Dr. Claude</string>
  <key>CFBundleIdentifier</key><string>com.drclaude.app</string>
  <key>CFBundleExecutable</key><string>Dr Claude</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# app icon from the app's own picture (best effort)
if [ -f "$ROOT/app/static/icon.png" ]; then
  ICS="$TMP/icon.iconset"; mkdir -p "$ICS"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/app/static/icon.png" --out "$ICS/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    d=$((s*2)); sips -z $d $d "$ROOT/app/static/icon.png" --out "$ICS/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$ICS" -o "$APPB/Contents/Resources/icon.icns" >/dev/null 2>&1 || true
fi
ln -sfn "$APPB" "$HOME/Desktop/Dr. Claude" 2>/dev/null || true

# 4. Uninstaller
cat > "$ROOT/Uninstall Dr. Claude.command" <<UNINST
#!/bin/bash
rm -rf "$APPB" "$HOME/Desktop/Dr. Claude" "$ROOT"
echo "Dr. Claude is uninstalled. Your class files in Documents/Dr. Claude are still there (delete that folder if you want)."
UNINST
chmod +x "$ROOT/Uninstall Dr. Claude.command"

say "Done! Opening Dr. Claude…"
printf 'It will open in your browser and walk you through setup.\nIf your Mac asks to let Dr. Claude use your Documents folder, click Allow.\nNext time, open it from Applications or the Dr. Claude icon on your Desktop.\n\n'
open "$APPB"
