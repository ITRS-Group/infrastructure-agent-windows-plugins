:: Batch script to automate the compilation <>
:: Copyright (C) 2003-2023 ITRS Group Ltd. All rights reserved

@echo off
setlocal EnableDelayedExpansion

set OUT_DIR=out
set PLUGIN_DIRS=csharp powershell

if EXIST %OUT_DIR% (
    echo [CLEAN] Cleaning up existing '%OUT_DIR%' directory
    RMDIR /S /Q %OUT_DIR% || echo [ERROR] Failed to clean OUT_DIR directory && exit /B 1
)
mkdir %OUT_DIR% || echo [ERROR] Failed to create OUT_DIR directory && exit /B 1

:: Expand OUT_DIR to a full path
For %%A in ("%OUT_DIR%") do (
    Set OUT_DIR=%%~fA
)

for %%d in (%PLUGIN_DIRS%) do (
   echo [BUILD] Building '%%d' plugins
   if not EXIST %%d\build.bat (
      echo [ERROR] Build batch file for '%%d' is missing! && exit /B 1
   )
   pushd %%d || echo [ERROR] Plugin dir '%%d' is missing && exit /B 1
   call build.bat %OUT_DIR% || echo [ERROR] Failed to build '%%d' plugins && exit /B 1
   popd || echo [ERROR] Failed to popd back to original directory && exit /B 1
)

echo [SUCCESS] Infrastructure Agent Windows Plugins built!

exit /B 0
