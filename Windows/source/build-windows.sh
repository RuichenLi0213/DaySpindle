#!/bin/bash
# Builds DaySpindle for Windows from the sources in this folder (on a Mac; nothing here needs
# Windows) and puts it in the folder above, ready to upload to GitHub:
#
#   ../package/DaySpindle-<version>-Windows-x64.zip.001, .002, ...  the app, in parts under 25 MB
#                                                                    (GitHub's limit for files
#                                                                    added in the browser)
#   ../Start DaySpindle.cmd   on Windows: joins the parts, checks them (SHA-256) and unpacks the
#                             app into "DaySpindle for Windows" the first time, then opens it
#
# Build tools (Node.js, Electron and the Electron packager) are kept outside the project, in
#   ~/Library/Caches/DaySpindle-Windows-build
# so they're downloaded once and never packaged with the app.
set -euo pipefail
cd "$(dirname "$0")"
SRC="$(pwd -P)"
TOP="$(cd .. && pwd -P)"
TOOLS="${DAYSPINDLE_BUILD_TOOLS:-$HOME/Library/Caches/DaySpindle-Windows-build}"
NODE_VERSION=24.22.2
ELECTRON_VERSION=45.2.3
PACKAGER_VERSION=20.3.0
PART_SIZE=20m
APP_VERSION=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$SRC/package.json" | head -1)
APPDIR="DaySpindle for Windows"
NAME="DaySpindle-$APP_VERSION-Windows-x64.zip"
NODE="$TOOLS/tools/node/bin/node"

# ---------------------------------------------------------------- 1. Build tools
if [ ! -x "$NODE" ]; then
  echo "Downloading Node.js $NODE_VERSION (build tool only)..."
  case "$(uname -m)" in arm64) NARCH=arm64 ;; *) NARCH=x64 ;; esac
  NNAME="node-v$NODE_VERSION-darwin-$NARCH"
  mkdir -p "$TOOLS/tools"
  curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/$NNAME.tar.gz" -o "$TOOLS/tools/$NNAME.tar.gz"
  curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" -o "$TOOLS/tools/SHASUMS256.txt"
  (cd "$TOOLS/tools" && grep " $NNAME.tar.gz\$" SHASUMS256.txt | shasum -a 256 -c -) || { echo "Node.js checksum mismatch"; exit 1; }
  rm -rf "$TOOLS/tools/node" && mkdir -p "$TOOLS/tools/node"
  tar -xzf "$TOOLS/tools/$NNAME.tar.gz" -C "$TOOLS/tools/node" --strip-components 1
  rm "$TOOLS/tools/$NNAME.tar.gz"
fi
export PATH="$TOOLS/tools/node/bin:$PATH"
if [ ! -d "$TOOLS/node_modules/@electron/packager" ] || [ ! -x "$TOOLS/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron" ]; then
  echo "Installing Electron $ELECTRON_VERSION and @electron/packager $PACKAGER_VERSION (build tools only)..."
  [ -f "$TOOLS/package.json" ] || echo '{ "private": true }' > "$TOOLS/package.json"
  (cd "$TOOLS" && npm install --no-audit --no-fund "electron@$ELECTRON_VERSION" "@electron/packager@$PACKAGER_VERSION")
fi

# ---------------------------------------------------------------- 2. Package for Windows (x64)
ICON="$SRC/app/icons/DaySpindle.ico"
[ -f "$ICON" ] || { echo "Missing $ICON"; exit 1; }
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
echo "Packaging DaySpindle $APP_VERSION for Windows (x64, Electron $ELECTRON_VERSION)..."
"$NODE" "$TOOLS/node_modules/@electron/packager/bin/electron-packager.mjs" "$SRC" DaySpindle \
  --platform=win32 --arch=x64 --electron-version="$ELECTRON_VERSION" \
  --out="$STAGE" --overwrite --asar --no-prune --quiet \
  --icon="$ICON" --executable-name=DaySpindle \
  --app-version="$APP_VERSION" --build-version="$APP_VERSION" --app-copyright="Copyright (c) 2026 Ruichen Li" \
  --win32metadata.CompanyName="DaySpindle" --win32metadata.FileDescription="DaySpindle" \
  --win32metadata.ProductName="DaySpindle" --win32metadata.InternalName="DaySpindle" \
  --win32metadata.OriginalFilename="DaySpindle.exe" \
  --ignore='^/node_modules($|/)' --ignore='^/package-lock\.json$' \
  --ignore='^/build-windows\.sh$' --ignore='\.DS_Store$'
[ -f "$STAGE/DaySpindle-win32-x64/DaySpindle.exe" ] || { echo "Packaging failed: no DaySpindle.exe"; exit 1; }
mv "$STAGE/DaySpindle-win32-x64" "$STAGE/$APPDIR"
cat > "$STAGE/$APPDIR/README.txt" <<TXT
DaySpindle $APP_VERSION for Windows

Start DaySpindle with "Start DaySpindle.cmd" in the folder above, or double-click
DaySpindle.exe here. Keep all files in this folder together.

Your groups, tasks and milestones are saved in a workspace: a folder you choose
(File > New Workspace... or Open Workspace...). On the first start, a folder named
"Example Workspace" or "Workspace" next to this folder (or next to the folder above it)
opens by itself.

Settings are kept in %APPDATA%\\DaySpindle\\settings.json.
See README.md in the folder above for everything else.
TXT
perl -pi -e 's/\n/\r\n/' "$STAGE/$APPDIR/README.txt"

# ---------------------------------------------------------------- 3. Zip, split into parts
echo "Zipping..."
(cd "$STAGE" && COPYFILE_DISABLE=1 zip -X -r -9 -q "$NAME" "$APPDIR" -x '*.DS_Store')
SHA256=$(shasum -a 256 "$STAGE/$NAME" | awk '{print toupper($1)}')
PKG="$TOP/package"
mkdir -p "$PKG"
rm -f "$PKG"/DaySpindle-*-Windows-x64.zip.[0-9][0-9][0-9]
(cd "$STAGE" && split -b "$PART_SIZE" "$NAME" "$NAME.part-")
PARTS=()
k=0
for f in "$STAGE/$NAME.part-"*; do
  k=$((k + 1))
  part=$(printf '%s.%03d' "$NAME" "$k")
  mv "$f" "$PKG/$part"
  PARTS+=("$part")
done

# ---------------------------------------------------------------- 4. The start script for Windows
NUMBERS=""
JOIN=""
for p in "${PARTS[@]}"; do
  NUMBERS="$NUMBERS ${p##*.}"
  JOIN="$JOIN${JOIN:+ + }\"package\\%NAME%.${p##*.}\""
done
NUMBERS="${NUMBERS# }"
CMD="$TOP/Start DaySpindle.cmd"
cat > "$CMD" <<CMDTEXT
@echo off
rem DaySpindle $APP_VERSION for Windows. Double-click this file to start DaySpindle.
rem The first time (and after an update), it joins the parts in the "package" folder,
rem checks the result (SHA-256) and unpacks the app into "DaySpindle for Windows".
rem After that it simply opens DaySpindle.
setlocal
cd /d "%~dp0"
set "NAME=$NAME"
set "SHA256=$SHA256"
set "APPDIR=$APPDIR"
set "MARK=%APPDIR%\\package-sha256.txt"

if not exist "%APPDIR%\\DaySpindle.exe" goto unpack
if not exist "%MARK%" goto unpack
set "HAVE="
set /p HAVE=<"%MARK%"
if /i "%HAVE%"=="%SHA256%" goto open

:unpack
echo DaySpindle: getting the app ready. The first time takes about a minute...
set "MISSING="
for %%n in ($NUMBERS) do if not exist "package\\%NAME%.%%n" (
  echo Missing part: package\\%NAME%.%%n
  set "MISSING=1"
)
if defined MISSING goto missing

set "ZIP=%TEMP%\\%NAME%"
copy /y /b $JOIN "%ZIP%" >nul
if errorlevel 1 goto failed
if not exist "%ZIP%" goto failed
set "HASH="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%ZIP%" SHA256') do if not defined HASH set "HASH=%%h"
if not defined HASH goto failed
set "HASH=%HASH: =%"
if /i not "%HASH%"=="%SHA256%" goto failed

set "UNPACK=%~dp0.unpacking"
if exist "%UNPACK%" rmdir /s /q "%UNPACK%"
mkdir "%UNPACK%"
if exist "%SystemRoot%\\System32\\tar.exe" "%SystemRoot%\\System32\\tar.exe" -xf "%ZIP%" -C "%UNPACK%"
if not exist "%UNPACK%\\%APPDIR%\\DaySpindle.exe" powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath \$env:ZIP -DestinationPath \$env:UNPACK -Force"
del "%ZIP%" >nul 2>&1
if not exist "%UNPACK%\\%APPDIR%\\DaySpindle.exe" goto failed

rem Replace an older copy of the app (your workspaces are elsewhere and are not touched).
if exist "%APPDIR%.old" rmdir /s /q "%APPDIR%.old"
if exist "%APPDIR%" ren "%APPDIR%" "%APPDIR%.old"
if exist "%APPDIR%" goto busy
move "%UNPACK%\\%APPDIR%" "%APPDIR%" >nul
rmdir /s /q "%UNPACK%"
if exist "%APPDIR%.old" rmdir /s /q "%APPDIR%.old"
> "%MARK%" echo %SHA256%
echo Done.

:open
start "" "%APPDIR%\\DaySpindle.exe"
exit /b 0

:missing
echo.
echo Some parts of the app are missing from the "package" folder.
echo Download or copy the whole DaySpindle folder again, then run this file again.
echo.
pause
exit /b 1

:busy
rmdir /s /q "%UNPACK%"
echo.
echo DaySpindle, or a window showing its folder, is open. Close it, then run this file again.
echo.
pause
exit /b 1

:failed
if exist "%ZIP%" del "%ZIP%"
if defined UNPACK if exist "%UNPACK%" rmdir /s /q "%UNPACK%"
echo.
echo The app could not be put together from the parts in the "package" folder:
echo one of them is probably incomplete. Download or copy the whole DaySpindle
echo folder again, then run this file again.
echo.
pause
exit /b 1
CMDTEXT
perl -pi -e 's/\r?\n/\r\n/' "$CMD"
LC_ALL=C grep -q '[^ -~[:space:]]' "$CMD" && { echo "Start DaySpindle.cmd must be plain ASCII"; exit 1; }

echo "Built DaySpindle $APP_VERSION for Windows:"
ls -l "$PKG" | awk 'NR > 1 {printf "  package/%s  %.1f MB\n", $9, $5 / 1048576}'
echo "  Start DaySpindle.cmd"
echo "  SHA-256 of $NAME: $SHA256"
