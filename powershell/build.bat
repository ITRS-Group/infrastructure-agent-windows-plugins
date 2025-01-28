:: Batch script to automate the compilation <>
:: Copyright (C) 2003-2025 ITRS Group Ltd. All rights reserved

@echo off
setlocal EnableDelayedExpansion


if [%1]==[] (
    set OUTPUT_DIR=%~dp0plugins
) else (
    set OUTPUT_DIR=%1
)

if NOT EXIST !OUTPUT_DIR! (
    mkdir %OUTPUT_DIR% || echo [ERROR] Failed to create OUTPUT_DIR directory && exit /B 1
)

echo [POWERSHELL] Building Powershell plugins
echo [BUILD] Installing plugins to '%OUTPUT_DIR%'

for %%p in (%~dp0\*.ps1) do (
    echo [BUILD] Installing %%~nxp
    xcopy /q "%%~fp" %OUTPUT_DIR% || echo [ERROR] Failed to copy '%%p' && exit /B 1
)

exit /B 0
