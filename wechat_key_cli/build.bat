@echo off
echo Setting up MSVC build environment...
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64

echo.
echo Forcefully terminating processes to release file locks...
taskkill /F /IM launcher.exe 2>nul
taskkill /F /IM Weixin.exe 2>nul
timeout /t 1 /nobreak > nul

echo.
echo Cleaning up previous build artifacts...
del launcher.exe /f /q 2>nul
del launcher.obj /f /q 2>nul

echo.
echo Compiling launcher.exe (Final Networked Version)...
cl.exe /MT /EHsc /O2 /utf-8 launcher.cpp /Fe:launcher.exe user32.lib advapi32.lib shlwapi.lib wininet.lib
if %errorlevel% neq 0 (
    echo ERROR: Launcher compilation failed.
    goto :eof
)
echo SUCCESS: launcher.exe compiled.

echo.
echo Build process completed successfully.
