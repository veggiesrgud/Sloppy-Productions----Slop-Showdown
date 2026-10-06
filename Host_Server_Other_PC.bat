@echo off
title Sloppy Showdown - Dedicated Server
cd /d "%~dp0"

echo ============================================
echo  Sloppy Showdown - Dedicated Server
echo ============================================
echo.
echo Your LAN IP (give this to the other PC):
ipconfig | findstr /C:"IPv4"
echo.
echo Port needed: 8080 TCP+UDP game, 8081 UDP browser
echo.

set GAME_EXE=
if exist "Sloppy Showdown.exe" set GAME_EXE=Sloppy Showdown.exe
if exist "SlopShowdown.exe" set GAME_EXE=SlopShowdown.exe
if exist "slop-showdown.exe" set GAME_EXE=slop-showdown.exe

if defined GAME_EXE (
  echo Found game: %GAME_EXE%
  echo Starting headless server...
  echo Close this window to stop the server.
  echo.
  "%GAME_EXE%" --headless "res://scenes/level/level.tscn"
  echo.
  echo Server stopped (code %errorlevel%).
  pause
  exit /b %errorlevel%
)

where godot >nul 2>nul
if %errorlevel%==0 (
  echo Found Godot in PATH, starting headless server from project...
  echo Close this window to stop the server.
  echo.
  godot --headless --path "%~dp0" "res://scenes/level/level.tscn"
  echo.
  echo Server stopped (code %errorlevel%).
  pause
  exit /b %errorlevel%
)

echo.
echo ERROR: no game exe found next to this .bat
echo Put this file in the SAME folder as your exported game exe, then run it.
echo To make that folder: Godot -^> Project -^> Export -^> Windows -^> Export,
echo then copy the .exe + .pck + this .bat to the other PC.
echo.
pause
exit /b 1
