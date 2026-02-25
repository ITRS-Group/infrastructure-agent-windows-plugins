:: Batch script to automate the compilation of the windows_agent_plugins
:: Copyright (C) 2003-2026 ITRS Group Ltd. All rights reserved

@echo off
setlocal EnableDelayedExpansion

set DOTNET=%SYSTEMROOT%\Microsoft.NET\Framework64\v4.0.30319
set CSC=%DOTNET%\csc.exe
set PLUGINS_DIR=windows_plugins

if [%1]==[] (
    (set OUTPUT_DIR=%~dp0plugins)
) else (
    set OUTPUT_DIR=%1
)

echo [CSHARP] Building C# plugins
echo [BUILD] Installing plugins to '%OUTPUT_DIR%'

if NOT EXIST %OUTPUT_DIR% (
    mkdir %OUTPUT_DIR% || echo [ERROR] Failed to create OUTPUT_DIR directory && exit /B 1
)

echo [BUILD] Installing plugins to '%OUTPUT_DIR%'

:: check_windows.exe
set source=%PLUGINS_DIR%\check_windows.cs
set dest=%OUTPUT_DIR%\check_windows.exe
set libs=PlugNSharp\*.cs Helpers\*.cs^
    %PLUGINS_DIR%\check_counter.cs^
    %PLUGINS_DIR%\check_cpu_load.cs^
    %PLUGINS_DIR%\check_drivesize.cs^
    %PLUGINS_DIR%\check_eventlog.cs^
    %PLUGINS_DIR%\check_http.cs^
    %PLUGINS_DIR%\check_memory.cs^
    %PLUGINS_DIR%\check_servicestate.cs^
    %PLUGINS_DIR%\check_services.cs^
    %PLUGINS_DIR%\check_ssl.cs

%CSC% /define:LONG_RUNNING /win32icon:icon.ico /optimize+ /debug+ /t:exe /out:!dest! !source! !libs! || echo [ERROR] Failed to compile !dest! && exit /B 1

:: check_capacity_planner.exe
set source=%PLUGINS_DIR%\check_capacity_planner.cs
set dest=%OUTPUT_DIR%\check_capacity_planner.exe
set libs=PlugNSharp\*.cs Helpers\*.cs
%CSC% /win32icon:icon.ico /optimize+ /debug+ /t:exe /out:!dest! !source! !libs! || echo [ERROR] Failed to compile !dest! && exit /B 1

ENDLOCAL
exit /B 0
