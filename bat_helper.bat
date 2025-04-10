@echo off
REM --- Runs the PowerShell script in the same directory ---

REM Get the directory where this batch file is located
set SCRIPT_DIR=%~dp0

REM Execute the PowerShell script, bypassing execution policy for this run only
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%powershell-helper.ps1"

REM Optional: Pause to see any output/errors before the window closes
echo.
echo Script execution finished. Press any key to close this window...
pause >nul