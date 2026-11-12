@echo off
rem DaySpindle 2.1.0 for Windows. Double-click this file to start DaySpindle.
rem The first time (and after an update), it joins the parts in the "package" folder,
rem checks the result (SHA-256) and unpacks the app into "DaySpindle for Windows".
rem After that it simply opens DaySpindle.
setlocal
cd /d "%~dp0"
set "NAME=DaySpindle-2.1.0-Windows-x64.zip"
set "SHA256=DE19C6AA22A6180E36F9C6AC4126B949BAFF566D969781560B86B9BDBA0EAF62"
set "APPDIR=DaySpindle for Windows"
set "MARK=%APPDIR%\package-sha256.txt"

if not exist "%APPDIR%\DaySpindle.exe" goto unpack
if not exist "%MARK%" goto unpack
set "HAVE="
set /p HAVE=<"%MARK%"
if /i "%HAVE%"=="%SHA256%" goto open

:unpack
echo DaySpindle: getting the app ready. The first time takes about a minute...
set "MISSING="
for %%n in (001 002 003 004 005 006 007 008) do if not exist "package\%NAME%.%%n" (
  echo Missing part: package\%NAME%.%%n
  set "MISSING=1"
)
if defined MISSING goto missing

set "ZIP=%TEMP%\%NAME%"
copy /y /b "package\%NAME%.001" + "package\%NAME%.002" + "package\%NAME%.003" + "package\%NAME%.004" + "package\%NAME%.005" + "package\%NAME%.006" + "package\%NAME%.007" + "package\%NAME%.008" "%ZIP%" >nul
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
if exist "%SystemRoot%\System32\tar.exe" "%SystemRoot%\System32\tar.exe" -xf "%ZIP%" -C "%UNPACK%"
if not exist "%UNPACK%\%APPDIR%\DaySpindle.exe" powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath $env:ZIP -DestinationPath $env:UNPACK -Force"
del "%ZIP%" >nul 2>&1
if not exist "%UNPACK%\%APPDIR%\DaySpindle.exe" goto failed

rem Replace an older copy of the app (your workspaces are elsewhere and are not touched).
if exist "%APPDIR%.old" rmdir /s /q "%APPDIR%.old"
if exist "%APPDIR%" ren "%APPDIR%" "%APPDIR%.old"
if exist "%APPDIR%" goto busy
move "%UNPACK%\%APPDIR%" "%APPDIR%" >nul
rmdir /s /q "%UNPACK%"
if exist "%APPDIR%.old" rmdir /s /q "%APPDIR%.old"
> "%MARK%" echo %SHA256%
echo Done.

:open
start "" "%APPDIR%\DaySpindle.exe"
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
