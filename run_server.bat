@echo off
cd /d "%~dp0"
where godot >nul 2>nul
if %errorlevel%==0 (
  echo Starting headless server with Godot...
  godot --headless --path "%~dp0" "res://scenes/level/level.tscn"
) else (
  echo Godot not in PATH. Trying exported build...
  if exist "SlopShowdown.exe" (
    SlopShowdown.exe --headless "res://scenes/level/level.tscn"
  ) else if exist "Sloppy Showdown.exe" (
    "Sloppy Showdown.exe" --headless "res://scenes/level/level.tscn"
  ) else (
    echo.
    echo ERROR: godot not found in PATH and no exported exe found.
    echo Either add Godot to PATH or export the project and place the exe here.
    echo See: https://docs.godotengine.org/en/stable/tutorials/export/index.html
    pause
    exit /b 1
  )
)
pause
