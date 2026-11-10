@echo off
rem DaySpindle for Windows: joins the 16 parts in this folder back into
rem DaySpindle-2.0-Windows-x64.zip with the copy command built into Windows,
rem then checks that the result is complete (SHA-256).
setlocal
cd /d "%~dp0"
set "NAME=DaySpindle-2.0-Windows-x64.zip"
set "SHA256=A5D5160303DCB51F063E55D4AD183779F9D5681DE4C5EE7C166FDA37A81DE3F4"

set "MISSING="
for %%n in (001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016) do (
  if not exist "%NAME%.%%n" (
    echo Missing part: %NAME%.%%n
    set "MISSING=1"
  )
)
if defined MISSING goto missing

echo Joining the 16 parts...
copy /y /b "%NAME%.001" + "%NAME%.002" + "%NAME%.003" + "%NAME%.004" + "%NAME%.005" + "%NAME%.006" + "%NAME%.007" + "%NAME%.008" + "%NAME%.009" + "%NAME%.010" + "%NAME%.011" + "%NAME%.012" + "%NAME%.013" + "%NAME%.014" + "%NAME%.015" + "%NAME%.016" "%NAME%" >nul
if errorlevel 1 goto failed
if not exist "%NAME%" goto failed

echo Checking the result...
set "HASH="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%NAME%" SHA256') do if not defined HASH set "HASH=%%h"
if not defined HASH goto failed
set "HASH=%HASH: =%"
if /i not "%HASH%"=="%SHA256%" goto failed

echo.
echo Done. %NAME% is ready in this folder.
echo Right-click it, choose Extract All, and follow "Getting started" in the README.
echo You can delete the 16 parts now.
echo.
pause
exit /b 0

:missing
echo.
echo Put all 16 parts, %NAME%.001 to %NAME%.016, in this folder
echo with their names unchanged, then run this file again.
echo.
pause
exit /b 1

:failed
if exist "%NAME%" del "%NAME%"
echo.
echo The parts could not be joined into a complete zip. One of them is probably incomplete.
echo Download the parts again into this folder, then run this file again.
echo.
pause
exit /b 1
