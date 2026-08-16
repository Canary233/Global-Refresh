[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$properties = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $moduleRoot 'module.prop')) {
    if ($line -match '^([^#=]+)=(.*)$') {
        $properties[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}

$version = $properties['version']
if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'module.prop 缺少 version。'
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$archive = Join-Path $OutputDirectory ("global_refresh-v{0}.zip" -f $version)
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}

$moduleEntries = @(
    'bin', 'src', 'webroot', 'customize.sh', 'global-refresh.sh', 'module.prop',
    'refresh-common.sh', 'refresh-webui.sh', 'refresh.conf', 'service.sh', 'uninstall.sh'
) | ForEach-Object { Join-Path $moduleRoot $_ }

Compress-Archive -Path $moduleEntries -DestinationPath $archive -CompressionLevel Optimal
Get-FileHash -Algorithm SHA256 -LiteralPath $archive
