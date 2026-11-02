$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location -LiteralPath $PSScriptRoot

if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Build on native Windows x64 using 64-bit PowerShell.'
}
$pythonDir = '.cache\python\windows-amd64'
$wheelDir = '.cache\wheels\windows-amd64'
$outputDir = 'dist\windows-amd64'
$buildDir = 'build\windows-amd64'
New-Item -ItemType Directory -Force -Path $pythonDir,$wheelDir,$outputDir,$buildDir | Out-Null
$env:PYTHONNOUSERSITE = '1'
$env:PYTHONUTF8 = '1'
$env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
$env:PIP_CACHE_DIR = Join-Path $PWD '.cache\pip\windows-amd64'
$env:PYINSTALLER_CONFIG_DIR = Join-Path $PWD 'build\windows-amd64\cache'
Remove-Item Env:PYTHONHOME,Env:PYTHONPATH -ErrorAction SilentlyContinue

$archive = '.cache\python\cpython-3.12.15+20261021-x86_64-pc-windows-msvc-install_only_stripped.tar.gz'
if (-not (Test-Path -LiteralPath $archive)) {
    & curl.exe -fL --retry 3 --connect-timeout 20 `
        'https://github.com/astral-sh/python-build-standalone/releases/download/20261021/cpython-3.12.15%2B20261021-x86_64-pc-windows-msvc-install_only_stripped.tar.gz' `
        -o "$archive.part"
    if ($LASTEXITCODE -ne 0) { throw "Python download failed: exit $LASTEXITCODE" }
    Move-Item -LiteralPath "$archive.part" -Destination $archive
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant() -ne 'aac5d331fc3307343f95928fdbea4583f0d53973d08c7e1d081884fbd229a0e1') {
    throw 'Python archive SHA256 mismatch.'
}
if (-not (Test-Path -LiteralPath "$pythonDir\.extracted")) {
    & tar.exe -xzf $archive -C $pythonDir
    if ($LASTEXITCODE -ne 0) { throw "Python extraction failed: exit $LASTEXITCODE" }
    New-Item -ItemType File -Path "$pythonDir\.extracted" | Out-Null
}
$python = Join-Path $PWD '.venv-windows-amd64\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & "$pythonDir\python\python.exe" -m venv --copies .venv-windows-amd64
    if ($LASTEXITCODE -ne 0) { throw "venv creation failed: exit $LASTEXITCODE" }
}

& $python -m pip download --no-index --find-links $wheelDir `
    --require-hashes --only-binary=:all: --dest $wheelDir -r requirements-windows.lock
if ($LASTEXITCODE -ne 0) {
    Write-Output 'Local wheel cache is incomplete; fetching locked dependencies from PyPI.'
    & $python -m pip download --index-url https://pypi.org/simple --retries 3 --timeout 60 `
        --require-hashes --only-binary=:all: --dest $wheelDir -r requirements-windows.lock
}
if ($LASTEXITCODE -ne 0) { throw "Dependency download failed: exit $LASTEXITCODE" }
& $python -m pip install --no-index --find-links $wheelDir --require-hashes --only-binary=:all: -r requirements-windows.lock
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed: exit $LASTEXITCODE" }
& $python -m pip check
if ($LASTEXITCODE -ne 0) { throw 'Dependency check failed.' }

# Separate stdout/stderr logs avoid PowerShell 5.1 treating normal PyInstaller
# stderr progress messages as terminating PowerShell errors.
$process = Start-Process -FilePath $python -ArgumentList @(
    '-m', 'PyInstaller', '--clean', '--noconfirm', '--distpath', $outputDir,
    '--workpath', "$buildDir\pyinstaller", 'modelscope_windows.spec'
) -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput "$buildDir\pyinstaller.stdout.log" `
    -RedirectStandardError "$buildDir\pyinstaller.stderr.log"
if ($process.ExitCode -ne 0) {
    Get-Content -LiteralPath "$buildDir\pyinstaller.stderr.log" -Tail 60
    throw "PyInstaller failed: exit $($process.ExitCode)"
}
& $python test\audit_pe.py "$outputDir\modelscope.exe"
if ($LASTEXITCODE -ne 0) { throw 'PE/DLL audit failed.' }
$version = & "$outputDir\modelscope.exe" --version
if ($LASTEXITCODE -ne 0) { throw 'Bundled executable version check failed.' }

Copy-Item -LiteralPath README.md,requirements-windows.lock -Destination $outputDir
@(
    "Build host: $env:COMPUTERNAME"
    "OS: $([Environment]::OSVersion.VersionString)"
    'Native architecture: Windows x64'
    'Python distribution: python-build-standalone 20261021, CPython 3.12.15'
    'Bootloader: PyInstaller 6.22.3 Windows x64, no UPX, no administrator manifest'
    $version
    'Packaging: onefile; Python, CA certificates and VC runtime bundled; Windows system DLLs required'
) | Set-Content -LiteralPath "$outputDir\build-info.txt" -Encoding UTF8
$files = @('modelscope.exe','README.md','requirements-windows.lock','build-info.txt')
$sums = foreach ($file in $files) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$outputDir\$file").Hash.ToLowerInvariant()
    "$hash  $file"
}
$sums | Set-Content -LiteralPath "$outputDir\SHA256SUMS" -Encoding ASCII
$packageFiles = @($files + 'SHA256SUMS' | ForEach-Object { Join-Path $outputDir $_ })
Compress-Archive -LiteralPath $packageFiles -DestinationPath 'dist\modelscope-windows-amd64.zip' -Force
Write-Output "Built: $outputDir\modelscope.exe"
Write-Output 'Archive: dist\modelscope-windows-amd64.zip'
