# Builds 1nstall 4.0: the Rust engine, then one .NET Framework executable that carries it.
# Needs a Rust toolchain; the C# side uses only the compiler and MSBuild that ship with Windows.
param([string]$Out='')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Out) { $Out = Join-Path $root 'dist\v4' }
New-Item -ItemType Directory -Path (Join-Path $Out 'src') -Force | Out-Null
$Out = (Resolve-Path $Out).Path

Push-Location (Join-Path $root 'engine')
try {
    # cargo reports progress on stderr; only its exit code decides success.
    $ErrorActionPreference = 'Continue'
    & cargo build --release --locked -p oneinstall-ffi 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'Engine build failed.' }
} finally { Pop-Location }
$target = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $root 'engine\target' }
$engine = Join-Path $target 'release\oneinstall_engine.dll'
if (-not (Test-Path -LiteralPath $engine)) { throw "Engine not found at $engine." }

# The interface is compiled exactly as build-windows.ps1 compiles it for 3.6.
$xaml = [IO.File]::ReadAllText((Join-Path $root 'interface.xaml')).Replace('<Window xmlns=', '<Window x:Class="OneInstall.MainWindow" xmlns=')
[IO.File]::WriteAllText((Join-Path $Out 'src\interface.xaml'), $xaml)
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe" (Join-Path $PSScriptRoot '1nstall.csproj') /nologo /verbosity:minimal "/p:Out=$Out" "/p:EngineDll=$engine"
if ($LASTEXITCODE -ne 0) { throw 'Application build failed.' }
Remove-Item -LiteralPath (Join-Path $Out 'obj'), (Join-Path $Out 'src') -Recurse -Force

$exe = Join-Path $Out '1nstall.exe'
$identity = [Reflection.AssemblyName]::GetAssemblyName($exe)
'{0} {1} | {2} bytes | sha256 {3}' -f $identity.Name, $identity.Version, (Get-Item -LiteralPath $exe).Length, (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
