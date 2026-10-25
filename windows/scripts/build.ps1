param([switch]$Test, [switch]$Publish)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$app = Join-Path $root 'windows/src/PigPendant.Windows/PigPendant.Windows.csproj'
$checks = Join-Path $root 'windows/tests/PigPendant.Core.Checks/PigPendant.Core.Checks.csproj'
$output = Join-Path $root 'dist/windows/single-file/win-x64'
$dotnet = 'dotnet'
& $dotnet build $app -c Release -p:NuGetAudit=false
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
if ($Test) {
    & $dotnet build $app -c Release -p:DefineConstants=TESTING -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw 'Windows smoke build failed' }
    & $dotnet run --project $checks -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Core checks failed' }
    $exe = Join-Path $root 'windows/src/PigPendant.Windows/bin/Release/net10.0-windows/PigPendant.Windows.exe'
    $check = Start-Process -FilePath $exe -ArgumentList '--self-check' -PassThru -Wait
    if ($check.ExitCode -ne 0) { throw 'Artwork/APNG check failed' }
    $pig = (Get-FileHash (Join-Path $root 'PigPendant/Resources/pig.png') -Algorithm SHA256).Hash
    if ($pig -ne '38973788538D53EEBCE385D48E90E01CC9B65C0E20C3C2909D2DE2688A423AFE') { throw 'Original pig.png changed' }
}
if ($Publish) {
    $cache = Join-Path $env:USERPROFILE '.nuget/packages'
    $packs = @('microsoft.netcore.app.runtime.win-x64', 'microsoft.windowsdesktop.app.runtime.win-x64', 'microsoft.aspnetcore.app.runtime.win-x64', 'microsoft.net.illink.tasks')
    $runtimeVersion = & $dotnet --list-runtimes | ForEach-Object { if ($_ -match '^Microsoft.NETCore.App (10\.\d+\.\d+) ') { $Matches[1] } } | Sort-Object { [version]$_ } | Select-Object -Last 1
    $cached = @($packs | Where-Object { -not (Test-Path (Join-Path $cache "$_/$runtimeVersion")) })
    $sourceArgs = if ($runtimeVersion -and $cached.Count -eq 0) { @('--source', $cache) } else { @() }
    & $dotnet publish $app -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false -p:NuGetAudit=false -o $output @sourceArgs
    if ($LASTEXITCODE -ne 0) { throw 'Self-contained publish failed' }
    $files = @(Get-ChildItem -LiteralPath $output -File)
    if ($files.Count -ne 1 -or $files[0].Name -ne 'PigPendant.Windows.exe') { throw 'Single-file publish emitted sidecar files' }
    $singleExe = Join-Path $root 'dist/PigPendant-Windows-win-x64.exe'
    Copy-Item -LiteralPath $files[0].FullName -Destination $singleExe -Force
    Write-Output "Published: $singleExe ($($files[0].Length) bytes)"
}
