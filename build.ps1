# Build script for PowerShell
$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Building Unique Permutations Engine" -ForegroundColor Cyan
Write-Host " C + x64 MASM Assembly with SSE2" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# Check if cl and ml64 are already available in PATH
$hasCl = Get-Command cl -ErrorAction SilentlyContinue
$hasMl64 = Get-Command ml64 -ErrorAction SilentlyContinue

if (-not ($hasCl -and $hasMl64)) {
    # Find vcvars64.bat using vswhere
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vsPath = $null
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath
    }

    if (-not $vsPath) {
        $candidates = @(
            "C:\Program Files\Microsoft Visual Studio\18\Community",
            "C:\Program Files\Microsoft Visual Studio\2022\Community",
            "C:\Program Files\Microsoft Visual Studio\2022\Professional",
            "C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) {
                $vsPath = $c
                break
            }
        }
    }

    if (-not $vsPath) {
        Write-Error "Visual Studio installation not found. Please run inside Developer Command Prompt."
        exit 1
    }

    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        Write-Error "Could not find vcvars64.bat at $vcvars"
        exit 1
    }

    Write-Host "Initializing MSVC x64 environment from:`n  $vcvars" -ForegroundColor Yellow
    
    # Import environment variables from vcvars64.bat
    $tempFile = [System.IO.Path]::GetTempFileName()
    cmd /c "call `"$vcvars`" >nul 2>&1 && set > `"$tempFile`""
    Get-Content $tempFile | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
    Remove-Item $tempFile -Force
}

# 1. Assemble hot_path.asm
Write-Host "`n[1/2] Assembling hot_path.asm with ml64..." -ForegroundColor Green
& ml64 /c /nologo /Fo hot_path.obj hot_path.asm
if ($LASTEXITCODE -ne 0) {
    Write-Error "Assembly failed!"
    exit 1
}
Write-Host "     hot_path.obj created successfully." -ForegroundColor Green

# 2. Compile and link
Write-Host "`n[2/2] Compiling unique_permutations.c and linking with cl..." -ForegroundColor Green
& cl /nologo /O2 /arch:SSE2 /W4 unique_permutations.c hot_path.obj /Fe:unique_perms.exe
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed!"
    exit 1
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " Build successful! Output: unique_perms.exe" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan
Write-Host "Examples to run:"
Write-Host "  .\unique_perms.exe"
Write-Host "  .\unique_perms.exe 1 1 2 2 3"
Write-Host "  python compare_all.py`n"
