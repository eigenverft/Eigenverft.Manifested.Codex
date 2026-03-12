<#
    Eigenverft.Manifested.Codex.NodeRuntimeAndCache
#>

function Get-NodeFlavor {
    [CmdletBinding()]
    param()

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'

    if ($archHints -match 'ARM64') {
        return 'win-arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'win-x64'
    }

    throw 'Only 64-bit Windows targets are supported by this bootstrap.'
}

function Get-NodeReleaseOnline {
    [CmdletBinding()]
    param(
        [string]$Flavor = (Get-NodeFlavor)
    )

    $response = Invoke-WebRequest -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $items = $response.Content | ConvertFrom-Json

    $release = $items |
        Where-Object { $_.lts -and $_.lts -ne $false } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText $_.version } } |
        Select-Object -First 1

    if (-not $release) {
        throw 'Unable to determine the latest Node.js LTS release.'
    }

    $fileName = 'node-{0}-{1}.zip' -f $release.version, $Flavor
    $baseUrl = 'https://nodejs.org/dist/{0}' -f $release.version

    [pscustomobject]@{
        Version     = $release.version
        Flavor      = $Flavor
        NpmVersion  = $release.npm
        FileName    = $fileName
        DownloadUrl = '{0}/{1}' -f $baseUrl, $fileName
        ShasumsUrl  = '{0}/SHASUMS256.txt' -f $baseUrl
    }
}

function Get-CachedNodeZipFiles {
    [CmdletBinding()]
    param(
        [string]$Flavor = (Get-NodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $mgr.NodeCacheRoot)) {
        return @()
    }

    $pattern = '^node-(v\d+\.\d+\.\d+)-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $mgr.NodeCacheRoot -File -Filter "*.zip" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            [pscustomobject]@{
                Version = $matches[1]
                Flavor  = $Flavor
                Path    = $_.FullName
                Name    = $_.Name
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-NodeVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedNodeZip {
    [CmdletBinding()]
    param(
        [string]$Flavor = (Get-NodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    return (Get-CachedNodeZipFiles -Flavor $Flavor -LocalRoot $LocalRoot | Select-Object -First 1)
}

function Get-ManagedNodeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -LocalRoot $LocalRoot
    return (Join-Path $mgr.NodeToolsRoot ($Version.TrimStart('v') + '\' + $Flavor))
}

function Test-ManagedNodeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeHome
    )

    $nodeExe = Join-Path $NodeHome 'node.exe'
    $npmCmd  = Join-Path $NodeHome 'npm.cmd'

    return (Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd)
}

function Get-NodeExpectedSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShasumsUrl,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $response = Invoke-WebRequest -Uri $ShasumsUrl -UseBasicParsing
    $line = ($response.Content -split "`n" | Where-Object { $_ -match ('\s' + [regex]::Escape($FileName) + '$') } | Select-Object -First 1)

    if (-not $line) {
        throw "Could not find SHA256 for $FileName."
    }

    return (($line -split '\s+')[0]).Trim().ToLowerInvariant()
}

function Ensure-NodeZip {
    [CmdletBinding()]
    param(
        [switch]$RefreshNode,
        [string]$Flavor = (Get-NodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -LocalRoot $LocalRoot
    Ensure-CodexDirectory -Path $mgr.NodeCacheRoot

    $onlineRelease = $null

    try {
        $onlineRelease = Get-NodeReleaseOnline -Flavor $Flavor
    }
    catch {
        $onlineRelease = $null
    }

    if ($onlineRelease) {
        $zipPath = Join-Path $mgr.NodeCacheRoot $onlineRelease.FileName

        if ($RefreshNode -or -not (Test-Path -LiteralPath $zipPath)) {
            Write-Host "Downloading Node.js $($onlineRelease.Version) ($Flavor)..."
            Invoke-WebRequest -Uri $onlineRelease.DownloadUrl -OutFile $zipPath -UseBasicParsing
        }

        $expectedHash = Get-NodeExpectedSha256 -ShasumsUrl $onlineRelease.ShasumsUrl -FileName $onlineRelease.FileName
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($actualHash -ne $expectedHash) {
            throw "SHA256 mismatch for $($onlineRelease.FileName)."
        }

        return [pscustomobject]@{
            Version    = $onlineRelease.Version
            Flavor     = $Flavor
            ZipPath    = $zipPath
            Source     = 'online'
            NpmVersion = $onlineRelease.NpmVersion
        }
    }

    $cached = Get-LatestCachedNodeZip -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cached) {
        throw 'Could not reach nodejs.org and no cached Node.js ZIP was found.'
    }

    return [pscustomobject]@{
        Version    = $cached.Version
        Flavor     = $Flavor
        ZipPath    = $cached.Path
        Source     = 'cache'
        NpmVersion = $null
    }
}

function Ensure-NodeRuntime {
    [CmdletBinding()]
    param(
        [switch]$RefreshNode,
        [string]$Flavor = (Get-NodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $zipInfo = Ensure-NodeZip -RefreshNode:$RefreshNode -Flavor $Flavor -LocalRoot $LocalRoot
    $nodeHome = Get-ManagedNodeHome -Version $zipInfo.Version -Flavor $zipInfo.Flavor -LocalRoot $LocalRoot

    if (-not (Test-ManagedNodeHome -NodeHome $nodeHome)) {
        $mgr = Get-CodexManagerLayout -LocalRoot $LocalRoot
        Ensure-CodexDirectory -Path (Split-Path -Parent $nodeHome)

        $tempExtractRoot = Join-Path $mgr.ToolsRoot ('_tmp_node_' + [Guid]::NewGuid().ToString('N'))
        Ensure-CodexDirectory -Path $tempExtractRoot

        try {
            Expand-Archive -LiteralPath $zipInfo.ZipPath -DestinationPath $tempExtractRoot -Force

            $expandedRoot = Get-ChildItem -LiteralPath $tempExtractRoot -Directory | Select-Object -First 1
            if (-not $expandedRoot) {
                throw 'The Node.js ZIP did not extract as expected.'
            }

            if (Test-Path -LiteralPath $nodeHome) {
                Remove-Item -LiteralPath $nodeHome -Recurse -Force
            }

            Ensure-CodexDirectory -Path $nodeHome

            Get-ChildItem -LiteralPath $expandedRoot.FullName -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $nodeHome -Force
            }
        }
        finally {
            if (Test-Path -LiteralPath $tempExtractRoot) {
                Remove-Item -LiteralPath $tempExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    [pscustomobject]@{
        Version    = $zipInfo.Version
        Flavor     = $zipInfo.Flavor
        NodeHome   = $nodeHome
        NodeExe    = (Join-Path $nodeHome 'node.exe')
        NpmCmd     = (Join-Path $nodeHome 'npm.cmd')
        Source     = $zipInfo.Source
        NpmVersion = $zipInfo.NpmVersion
    }
}
