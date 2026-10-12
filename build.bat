@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  Building Unique Permutations Engine
echo  C + x64 MASM Assembly with SSE2
echo ============================================
echo.

REM 1. Check if cl and ml64 are already available in PATH
where cl >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    where ml64 >nul 2>&1
    if %ERRORLEVEL% EQU 0 goto :tools_ready
)

REM 2. Find Visual Studio via vswhere if available
set "VS_DIR="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
    for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -property installationPath`) do (
        set "VS_DIR=%%i"
    )
)

REM 3. Fallback to hardcoded known Visual Studio locations
if not defined VS_DIR (
    if exist "C:\Program Files\Microsoft Visual Studio\18\Community" (
        set "VS_DIR=C:\Program Files\Microsoft Visual Studio\18\Community"
    ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community" (
        set "VS_DIR=C:\Program Files\Microsoft Visual Studio\2022\Community"
    ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional" (
        set "VS_DIR=C:\Program Files\Microsoft Visual Studio\2022\Professional"
    ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise" (
        set "VS_DIR=C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
    )
)

if not defined VS_DIR (
    echo ERROR: Visual Studio installation could not be found.
    echo Please run this script inside a Visual Studio Developer Command Prompt.
    exit /b 1
)

set "VCVARS=%VS_DIR%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo ERROR: Could not find vcvars64.bat at "%VCVARS%".
    exit /b 1
)

echo Initializing MSVC x64 environment from:
echo   "%VCVARS%"
call "%VCVARS%" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to configure MSVC environment with vcvars64.bat.
    exit /b 1
)

:tools_ready
REM Step 1: Assemble hot_path.asm
echo.
echo [1/2] Assembling hot_path.asm with ml64 ...
ml64 /c /nologo /Fo hot_path.obj hot_path.asm
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Assembly of hot_path.asm failed!
    exit /b 1
)
echo      hot_path.obj created successfully.

REM Step 2: Compile unique_permutations.c and link with hot_path.obj
echo.
echo [2/2] Compiling unique_permutations.c and linking with cl ...
cl /nologo /O2 /arch:SSE2 /W4 unique_permutations.c hot_path.obj /Fe:unique_perms.exe
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Compilation failed!
    exit /b 1
)

echo.
echo ============================================
echo  Build successful! Output: unique_perms.exe
echo ============================================
echo.
echo Examples to run:
echo   .\unique_perms.exe
echo   .\unique_perms.exe 1 1 2 2 3
echo   python compare_all.py
