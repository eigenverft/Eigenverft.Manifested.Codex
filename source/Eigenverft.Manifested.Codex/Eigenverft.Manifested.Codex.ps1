#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor `
        [Net.SecurityProtocolType]::Tls12
}
catch {
    # Best effort only. Older hosts may already be configured appropriately.
}

$script:CodexPackage = '@openai/codex'

function Get-CodexManagerLayout {
    [CmdletBinding()]
    param(
        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $slotsRootResolved = [System.IO.Path]::GetFullPath($SlotsRoot)
    $localRootResolved = [System.IO.Path]::GetFullPath($LocalRoot)

    [pscustomobject]@{
        SlotsRoot     = $slotsRootResolved
        LocalRoot     = $localRootResolved
        CacheRoot     = (Join-Path $localRootResolved 'cache')
        NodeCacheRoot = (Join-Path $localRootResolved 'cache\node')
        ToolsRoot     = (Join-Path $localRootResolved 'tools')
        NodeToolsRoot = (Join-Path $localRootResolved 'tools\node')
        StateFile     = (Join-Path $slotsRootResolved 'state.json')
    }
}

function Get-CodexSlotLayout {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $slotRoot = Join-Path $mgr.SlotsRoot $Name
    $npmPrefix = Join-Path $slotRoot 'npm'
    $slotMeta = Join-Path $slotRoot 'slot.json'
    $codexCmd = Join-Path $npmPrefix 'codex.cmd'
    $pkgJson = Join-Path $npmPrefix 'node_modules\@openai\codex\package.json'

    [pscustomobject]@{
        Name        = $Name
        SlotRoot    = $slotRoot
        NpmPrefix   = $npmPrefix
        SlotMeta    = $slotMeta
        CodexCmd    = $codexCmd
        PackageJson = $pkgJson
    }
}

function Ensure-CodexDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Normalize-CodexPath {
    [CmdletBinding()]
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ''
    }

    try {
        return [System.IO.Path]::GetFullPath($PathValue).Trim().TrimEnd('\').ToLowerInvariant()
    }
    catch {
        return $PathValue.Trim().TrimEnd('\').ToLowerInvariant()
    }
}

function Split-CodexPathEntries {
    [CmdletBinding()]
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return @()
    }

    return @(
        $PathValue -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() }
    )
}

function Test-CodexPathContains {
    [CmdletBinding()]
    param(
        [string]$PathValue,
        [string]$Needle
    )

    $needleNorm = Normalize-CodexPath -PathValue $Needle
    foreach ($entry in (Split-CodexPathEntries -PathValue $PathValue)) {
        if ((Normalize-CodexPath -PathValue $entry) -eq $needleNorm) {
            return $true
        }
    }

    return $false
}

function Remove-CodexManagedPathEntries {
    [CmdletBinding()]
    param(
        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $slotsRootNorm = Normalize-CodexPath -PathValue $mgr.SlotsRoot
    $nodeToolsRootNorm = Normalize-CodexPath -PathValue $mgr.NodeToolsRoot

    foreach ($scope in @('User', 'Process')) {
        $current = [Environment]::GetEnvironmentVariable('Path', $scope)
        $filtered = New-Object System.Collections.Generic.List[string]

        foreach ($entry in (Split-CodexPathEntries -PathValue $current)) {
            $entryNorm = Normalize-CodexPath -PathValue $entry

            $isManagedSlotPath = $entryNorm.StartsWith($slotsRootNorm)
            $isManagedNodePath = $entryNorm.StartsWith($nodeToolsRootNorm)

            if (-not $isManagedSlotPath -and -not $isManagedNodePath) {
                [void]$filtered.Add($entry)
            }
        }

        [Environment]::SetEnvironmentVariable('Path', (($filtered | Select-Object -Unique) -join ';'), $scope)
    }

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Process')
}

function Set-CodexManagedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeHome,

        [Parameter(Mandatory = $true)]
        [string]$SlotPrefix,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    Remove-CodexManagedPathEntries -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    foreach ($scope in @('User', 'Process')) {
        $current = [Environment]::GetEnvironmentVariable('Path', $scope)
        $entries = Split-CodexPathEntries -PathValue $current
        $newEntries = @($NodeHome, $SlotPrefix) + $entries
        $newPath = ($newEntries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, $scope)
    }

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Process')
}

function Get-CodexManagerState {
    [CmdletBinding()]
    param(
        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    if (-not (Test-Path -LiteralPath $mgr.StateFile)) {
        return [pscustomobject]@{
            ActiveSlot   = $null
            NodeVersion  = $null
            NodeFlavor   = $null
            UpdatedUtc   = $null
        }
    }

    try {
        return (Get-Content -LiteralPath $mgr.StateFile -Raw | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            ActiveSlot   = $null
            NodeVersion  = $null
            NodeFlavor   = $null
            UpdatedUtc   = $null
        }
    }
}

function Save-CodexManagerState {
    [CmdletBinding()]
    param(
        [string]$ActiveSlot,
        [string]$NodeVersion,
        [string]$NodeFlavor,
        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    Ensure-CodexDirectory -Path $mgr.SlotsRoot

    [pscustomobject]@{
        ActiveSlot   = $ActiveSlot
        NodeVersion  = $NodeVersion
        NodeFlavor   = $NodeFlavor
        UpdatedUtc   = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $mgr.StateFile -Encoding UTF8
}

function Get-CodexSlotMetadata {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $slot = Get-CodexSlotLayout -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    if (-not (Test-Path -LiteralPath $slot.SlotMeta)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $slot.SlotMeta -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Save-CodexSlotMetadata {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$NodeVersion,

        [Parameter(Mandatory = $true)]
        [string]$NodeFlavor,

        [Parameter(Mandatory = $true)]
        [string]$CodexVersion,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $slot = Get-CodexSlotLayout -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    Ensure-CodexDirectory -Path $slot.SlotRoot

    [pscustomobject]@{
        Name         = $Name
        NodeVersion  = $NodeVersion
        NodeFlavor   = $NodeFlavor
        CodexVersion = $CodexVersion
        UpdatedUtc   = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $slot.SlotMeta -Encoding UTF8
}

function Get-CodexNodeFlavor {
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

function ConvertTo-CodexVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    return [version]($VersionText -replace '^v', '')
}

function Get-CodexNodeReleaseOnline {
    [CmdletBinding()]
    param(
        [string]$Flavor = (Get-CodexNodeFlavor)
    )

    $response = Invoke-WebRequest -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $items = $response.Content | ConvertFrom-Json

    $release = $items |
        Where-Object { $_.lts -and $_.lts -ne $false } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-CodexVersion -VersionText $_.version } } |
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
        [string]$Flavor = (Get-CodexNodeFlavor),
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
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-CodexVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedNodeZip {
    [CmdletBinding()]
    param(
        [string]$Flavor = (Get-CodexNodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    return (Get-CachedNodeZipFiles -Flavor $Flavor -LocalRoot $LocalRoot | Select-Object -First 1)
}

function Get-CodexManagedNodeHome {
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

function Test-CodexManagedNodeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeHome
    )

    $nodeExe = Join-Path $NodeHome 'node.exe'
    $npmCmd  = Join-Path $NodeHome 'npm.cmd'

    return (Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd)
}

function Get-CodexNodeExpectedSha256 {
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

function Ensure-CodexNodeZip {
    [CmdletBinding()]
    param(
        [switch]$RefreshNode,
        [string]$Flavor = (Get-CodexNodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -LocalRoot $LocalRoot
    Ensure-CodexDirectory -Path $mgr.NodeCacheRoot

    $onlineRelease = $null

    try {
        $onlineRelease = Get-CodexNodeReleaseOnline -Flavor $Flavor
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

        $expectedHash = Get-CodexNodeExpectedSha256 -ShasumsUrl $onlineRelease.ShasumsUrl -FileName $onlineRelease.FileName
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

function Ensure-CodexNodeRuntime {
    [CmdletBinding()]
    param(
        [switch]$RefreshNode,
        [string]$Flavor = (Get-CodexNodeFlavor),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $zipInfo = Ensure-CodexNodeZip -RefreshNode:$RefreshNode -Flavor $Flavor -LocalRoot $LocalRoot
    $nodeHome = Get-CodexManagedNodeHome -Version $zipInfo.Version -Flavor $zipInfo.Flavor -LocalRoot $LocalRoot

    if (-not (Test-CodexManagedNodeHome -NodeHome $nodeHome)) {
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

function Get-CodexPackageVersionFromSlot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    if (-not (Test-Path -LiteralPath $PackageJsonPath)) {
        return $null
    }

    try {
        return ((Get-Content -LiteralPath $PackageJsonPath -Raw | ConvertFrom-Json).version)
    }
    catch {
        return $null
    }
}

function Install-CodexIntoSlot {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$NodeVersion,

        [Parameter(Mandatory = $true)]
        [string]$NodeFlavor,

        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [switch]$ForceCodex,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $slot = Get-CodexSlotLayout -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    Ensure-CodexDirectory -Path $slot.SlotRoot
    Ensure-CodexDirectory -Path $slot.NpmPrefix

    $needsInstall = $ForceCodex -or -not (Test-Path -LiteralPath $slot.CodexCmd)

    if ($needsInstall) {
        Write-Host "Installing Codex CLI into slot '$Name'..."
        & $NpmCmd install -g --prefix $slot.NpmPrefix ($script:CodexPackage + '@latest')
    }

    $codexVersion = Get-CodexPackageVersionFromSlot -PackageJsonPath $slot.PackageJson
    if (-not $codexVersion) {
        $codexVersion = 'installed'
    }

    Save-CodexSlotMetadata `
        -Name $Name `
        -NodeVersion $NodeVersion `
        -NodeFlavor $NodeFlavor `
        -CodexVersion $codexVersion `
        -SlotsRoot $SlotsRoot `
        -LocalRoot $LocalRoot

    return [pscustomobject]@{
        Name         = $Name
        NodeVersion  = $NodeVersion
        NodeFlavor   = $NodeFlavor
        CodexVersion = $codexVersion
        CodexCmd     = $slot.CodexCmd
        NpmPrefix    = $slot.NpmPrefix
    }
}

function Use-CodexSlot {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name = 'default',

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $slot = Get-CodexSlotLayout -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $slot.CodexCmd)) {
        throw "Slot '$Name' is not installed. Run codex-init -Name $Name first."
    }

    $meta = Get-CodexSlotMetadata -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    if (-not $meta -or -not $meta.NodeVersion -or -not $meta.NodeFlavor) {
        throw "Slot '$Name' has no Node metadata. Re-run codex-init -Name $Name."
    }

    $nodeHome = Get-CodexManagedNodeHome -Version $meta.NodeVersion -Flavor $meta.NodeFlavor -LocalRoot $LocalRoot
    if (-not (Test-CodexManagedNodeHome -NodeHome $nodeHome)) {
        throw "Managed Node runtime for slot '$Name' is missing. Re-run codex-init -Name $Name."
    }

    Set-CodexManagedPath -NodeHome $nodeHome -SlotPrefix $slot.NpmPrefix -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    Save-CodexManagerState -ActiveSlot $Name -NodeVersion $meta.NodeVersion -NodeFlavor $meta.NodeFlavor -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    [pscustomobject]@{
        ActiveSlot   = $Name
        NodeVersion  = $meta.NodeVersion
        NodeFlavor   = $meta.NodeFlavor
        NodeHome     = $nodeHome
        CodexCmd     = $slot.CodexCmd
    }
}

function Initialize-CodexSlot {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name = 'default',

        [switch]$RefreshNode,
        [switch]$ForceCodex,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $runtime = Ensure-CodexNodeRuntime -RefreshNode:$RefreshNode -LocalRoot $LocalRoot

    Install-CodexIntoSlot `
        -Name $Name `
        -NodeVersion $runtime.Version `
        -NodeFlavor $runtime.Flavor `
        -NpmCmd $runtime.NpmCmd `
        -ForceCodex:$ForceCodex `
        -SlotsRoot $SlotsRoot `
        -LocalRoot $LocalRoot | Out-Null

    Use-CodexSlot -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot | Out-Null

    return (Test-CodexSlot -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot)
}

function Test-CodexSlot {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name = 'default',

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $slot = Get-CodexSlotLayout -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $meta = Get-CodexSlotMetadata -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $manager = Get-CodexManagerState -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    $slotInstalled = Test-Path -LiteralPath $slot.CodexCmd
    $nodeHome = $null
    $nodeExe = $null
    $npmCmd = $null
    $nodeVersionText = $null
    $codexVersionText = $null

    if ($meta) {
        $nodeHome = Get-CodexManagedNodeHome -Version $meta.NodeVersion -Flavor $meta.NodeFlavor -LocalRoot $LocalRoot
        $nodeExe = Join-Path $nodeHome 'node.exe'
        $npmCmd = Join-Path $nodeHome 'npm.cmd'

        if (Test-Path -LiteralPath $nodeExe) {
            try { $nodeVersionText = (& $nodeExe --version 2>$null | Select-Object -First 1) } catch { $nodeVersionText = $null }
        }

        if ($slotInstalled) {
            try { $codexVersionText = (& $slot.CodexCmd --version 2>$null | Select-Object -First 1) } catch { $codexVersionText = $null }
        }
    }

    $resolvedCodex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $resolvedCodex) {
        $resolvedCodex = Get-Command codex.cmd -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Name                = $Name
        SlotInstalled       = $slotInstalled
        ActiveSlot          = $manager.ActiveSlot
        ActiveSlotMatches   = ($manager.ActiveSlot -eq $Name)
        NodeVersion         = if ($meta) { $meta.NodeVersion } else { $null }
        NodeFlavor          = if ($meta) { $meta.NodeFlavor } else { $null }
        NodeHome            = $nodeHome
        NodeVersionText     = $nodeVersionText
        NpmCmd              = $npmCmd
        CodexCmd            = if ($slotInstalled) { $slot.CodexCmd } else { $null }
        CodexVersion        = if ($meta) { $meta.CodexVersion } else { $null }
        CodexVersionText    = $codexVersionText
        CodexResolvesOnPath = [bool]$resolvedCodex
        ResolvedCodexPath   = if ($resolvedCodex) { $resolvedCodex.Source } else { $null }
        ReadyToRun          = ($slotInstalled -and (Test-CodexManagedNodeHome -NodeHome $nodeHome))
        StartCommand        = 'codex'
    }
}

function Get-CodexSlots {
    [CmdletBinding()]
    param(
        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $manager = Get-CodexManagerState -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    if (-not (Test-Path -LiteralPath $mgr.SlotsRoot)) {
        return @()
    }

    $slots = Get-ChildItem -LiteralPath $mgr.SlotsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $meta = Get-CodexSlotMetadata -Name $_.Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
        $slot = Get-CodexSlotLayout -Name $_.Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

        [pscustomobject]@{
            Name         = $_.Name
            Active       = ($manager.ActiveSlot -eq $_.Name)
            Installed    = (Test-Path -LiteralPath $slot.CodexCmd)
            NodeVersion  = if ($meta) { $meta.NodeVersion } else { $null }
            NodeFlavor   = if ($meta) { $meta.NodeFlavor } else { $null }
            CodexVersion = if ($meta) { $meta.CodexVersion } else { $null }
            SlotRoot     = $slot.SlotRoot
            NpmPrefix    = $slot.NpmPrefix
            UpdatedUtc   = if ($meta) { $meta.UpdatedUtc } else { $null }
        }
    }

    return @($slots | Sort-Object Name)
}

function Remove-CodexSlot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$Force,

        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    if (-not $Force) {
        throw "Pass -Force to remove slot '$Name'."
    }

    $slot = Get-CodexSlotLayout -Name $Name -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $manager = Get-CodexManagerState -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot

    if (-not (Test-Path -LiteralPath $slot.SlotRoot)) {
        throw "Slot '$Name' does not exist."
    }

    if ($PSCmdlet.ShouldProcess($slot.SlotRoot, "Remove Codex slot '$Name'")) {
        if ($manager.ActiveSlot -eq $Name) {
            Remove-CodexManagedPathEntries -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
            Save-CodexManagerState -ActiveSlot '' -NodeVersion '' -NodeFlavor '' -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
        }

        Remove-Item -LiteralPath $slot.SlotRoot -Recurse -Force
    }

    return Get-CodexSlots -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
}

function Get-CodexState {
    [CmdletBinding()]
    param(
        [string]$SlotsRoot = (Join-Path $HOME '.codex-slots'),
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $mgr = Get-CodexManagerLayout -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $manager = Get-CodexManagerState -SlotsRoot $SlotsRoot -LocalRoot $LocalRoot
    $flavor = Get-CodexNodeFlavor
    $cached = Get-LatestCachedNodeZip -Flavor $flavor -LocalRoot $LocalRoot

    $resolvedNode = Get-Command node -ErrorAction SilentlyContinue
    $resolvedNpm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $resolvedNpm) {
        $resolvedNpm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    }
    $resolvedCodex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $resolvedCodex) {
        $resolvedCodex = Get-Command codex.cmd -ErrorAction SilentlyContinue
    }

    $activeNodeHome = $null
    if ($manager.NodeVersion -and $manager.NodeFlavor) {
        $activeNodeHome = Get-CodexManagedNodeHome -Version $manager.NodeVersion -Flavor $manager.NodeFlavor -LocalRoot $LocalRoot
    }

    [pscustomobject]@{
        SlotsRoot         = $mgr.SlotsRoot
        LocalRoot         = $mgr.LocalRoot
        NodeCacheRoot     = $mgr.NodeCacheRoot
        NodeToolsRoot     = $mgr.NodeToolsRoot
        NodeFlavor        = $flavor
        CachedNodeVersion = if ($cached) { $cached.Version } else { $null }
        CachedNodeZip     = if ($cached) { $cached.Path } else { $null }
        ActiveSlot        = $manager.ActiveSlot
        ActiveNodeVersion = $manager.NodeVersion
        ActiveNodeFlavor  = $manager.NodeFlavor
        ActiveNodeHome    = $activeNodeHome
        NodeOnPath        = if ($resolvedNode) { $resolvedNode.Source } else { $null }
        NpmOnPath         = if ($resolvedNpm) { $resolvedNpm.Source } else { $null }
        CodexOnPath       = if ($resolvedCodex) { $resolvedCodex.Source } else { $null }
        ReadyToInit       = $true
        ReadyToRun        = [bool]$resolvedCodex
    }
}

function Resolve-CodexCommandPath {
    [CmdletBinding()]
    param()

    $resolvedCodex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $resolvedCodex) {
        $resolvedCodex = Get-Command codex.cmd -ErrorAction SilentlyContinue
    }

    if (-not $resolvedCodex) {
        throw 'codex was not found on PATH. Activate a slot with codex-use or run codex-init.'
    }

    return $resolvedCodex.Source
}

function Resolve-CodexDirectory {
    [CmdletBinding()]
    param(
        [string]$Directory = (Get-Location).ProviderPath
    )

    $resolvedPaths = @(Resolve-Path -LiteralPath $Directory -ErrorAction Stop)

    if ($resolvedPaths.Count -ne 1) {
        throw "Directory path '$Directory' resolved to multiple locations."
    }

    $path = $resolvedPaths[0].ProviderPath
    if (-not $path) {
        $path = $resolvedPaths[0].Path
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Directory '$Directory' does not exist or is not a directory."
    }

    return [System.IO.Path]::GetFullPath($path)
}

function Get-CodexSessionStorePath {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    $dir = Join-Path $LocalRoot 'sessions'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    return (Join-Path $dir 'named-sessions.json')
}

function Get-CodexSession {
<#
.SYNOPSIS
Gets one or more stored Codex wrapper sessions.

.DESCRIPTION
Reads the local named session store used by the Codex PowerShell wrapper.

If SessionName is supplied, returns that single session if present.
If SessionName is omitted, returns all stored sessions.

.PARAMETER SessionName
Optional session name to fetch.
Alias: Session

.EXAMPLE
Get-CodexSession

.EXAMPLE
Get-CodexSession -SessionName foo99

.EXAMPLE
Get-CodexSession -Session foo99
#>
    [CmdletBinding()]
    param(
        [Alias('Session')]
        [string]$SessionName
    )

    $sessionStorePath = Join-Path $env:LOCALAPPDATA 'CodexSlots\sessions\named-sessions.json'

    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        if ($PSBoundParameters.ContainsKey('SessionName')) {
            return $null
        }

        return @()
    }

    $sessionMap = @{}

    try {
        $raw = Get-Content -LiteralPath $sessionStorePath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $sessionMap[$p.Name] = $p.Value
            }
        }
    }
    catch {
        throw "Failed to read session store: $sessionStorePath"
    }

    if ($PSBoundParameters.ContainsKey('SessionName')) {
        $sessionKey = ($SessionName.Trim() -replace '\|', '_')

        if (-not $sessionMap.ContainsKey($sessionKey)) {
            return $null
        }

        $value = $sessionMap[$sessionKey]

        return [pscustomobject]@{
            SessionName   = [string]$value.SessionName
            ThreadId      = [string]$value.ThreadId
            LastDirectory = [string]$value.LastDirectory
            UpdatedUtc    = [string]$value.UpdatedUtc
        }
    }

    $result = foreach ($key in ($sessionMap.Keys | Sort-Object)) {
        $value = $sessionMap[$key]

        [pscustomobject]@{
            SessionName   = [string]$value.SessionName
            ThreadId      = [string]$value.ThreadId
            LastDirectory = [string]$value.LastDirectory
            UpdatedUtc    = [string]$value.UpdatedUtc
        }
    }

    return @($result)
}

function Remove-CodexSession {
<#
.SYNOPSIS
Removes a stored Codex wrapper session.

.DESCRIPTION
Deletes a named session from the local session store.

This only removes the wrapper-side session mapping.
It does not delete any Codex-internal session history.

.PARAMETER SessionName
Name of the session to remove.
Alias: Session

.PARAMETER Force
Required switch to confirm deletion.

.EXAMPLE
Remove-CodexSession -SessionName foo99 -Force

.EXAMPLE
Remove-CodexSession -Session foo99 -Force
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Alias('Session')]
        [Parameter(Mandatory = $true)]
        [string]$SessionName,

        [switch]$Force
    )

    if (-not $Force) {
        throw "Pass -Force to remove session '$SessionName'."
    }

    $sessionStorePath = Join-Path $env:LOCALAPPDATA 'CodexSlots\sessions\named-sessions.json'

    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        return $false
    }

    $sessionMap = @{}

    try {
        $raw = Get-Content -LiteralPath $sessionStorePath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $sessionMap[$p.Name] = $p.Value
            }
        }
    }
    catch {
        throw "Failed to read session store: $sessionStorePath"
    }

    $sessionKey = ($SessionName.Trim() -replace '\|', '_')

    if (-not $sessionMap.ContainsKey($sessionKey)) {
        return $false
    }

    if ($PSCmdlet.ShouldProcess($sessionKey, "Remove stored Codex session")) {
        [void]$sessionMap.Remove($sessionKey)
        ($sessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sessionStorePath -Encoding UTF8
        return $true
    }

    return $false
}

function Set-CodexSessionDirectory {
<#
.SYNOPSIS
Updates the stored last directory for a Codex wrapper session.

.DESCRIPTION
Sets LastDirectory for an existing named session in the local session store.

This does not change Codex-internal session state directly.
It only changes the wrapper's remembered working directory.

.PARAMETER SessionName
Name of the session to update.
Alias: Session

.PARAMETER Directory
Directory to store as LastDirectory.

.EXAMPLE
Set-CodexSessionDirectory -SessionName foo99 -Directory C:\temp

.EXAMPLE
Set-CodexSessionDirectory -Session foo99 -Directory D:\project
#>
    [CmdletBinding()]
    param(
        [Alias('Session')]
        [Parameter(Mandatory = $true)]
        [string]$SessionName,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $sessionStorePath = Join-Path $env:LOCALAPPDATA 'CodexSlots\sessions\named-sessions.json'
    $resolvedDirectory = Resolve-CodexDirectory -Directory $Directory

    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        throw "Session store was not found: $sessionStorePath"
    }

    $sessionMap = @{}

    try {
        $raw = Get-Content -LiteralPath $sessionStorePath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $sessionMap[$p.Name] = $p.Value
            }
        }
    }
    catch {
        throw "Failed to read session store: $sessionStorePath"
    }

    $sessionKey = ($SessionName.Trim() -replace '\|', '_')

    if (-not $sessionMap.ContainsKey($sessionKey)) {
        throw "Session '$SessionName' was not found."
    }

    $existing = $sessionMap[$sessionKey]

    $sessionMap[$sessionKey] = @{
        SessionName   = [string]$existing.SessionName
        ThreadId      = [string]$existing.ThreadId
        LastDirectory = $resolvedDirectory
        UpdatedUtc    = [DateTime]::UtcNow.ToString('o')
    }

    ($sessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sessionStorePath -Encoding UTF8

    return [pscustomobject]@{
        SessionName   = [string]$sessionMap[$sessionKey].SessionName
        ThreadId      = [string]$sessionMap[$sessionKey].ThreadId
        LastDirectory = [string]$sessionMap[$sessionKey].LastDirectory
        UpdatedUtc    = [string]$sessionMap[$sessionKey].UpdatedUtc
    }
}

function Clear-CodexSessions {
<#
.SYNOPSIS
Clears all stored Codex wrapper sessions.

.DESCRIPTION
Deletes the local session store file used by the Codex PowerShell wrapper.

This only removes wrapper-side mappings.
It does not delete Codex-internal session history.

.PARAMETER Force
Required switch to confirm deletion.

.EXAMPLE
Clear-CodexSessions -Force
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Force
    )

    if (-not $Force) {
        throw 'Pass -Force to clear all stored sessions.'
    }

    $sessionStorePath = Join-Path $env:LOCALAPPDATA 'CodexSlots\sessions\named-sessions.json'

    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        return $false
    }

    if ($PSCmdlet.ShouldProcess($sessionStorePath, 'Remove all stored Codex sessions')) {
        Remove-Item -LiteralPath $sessionStorePath -Force
        return $true
    }

    return $false
}

function Invoke-CodexTask {
<#
.SYNOPSIS
Runs a Codex non-interactive task and maintains wrapper-level named session state.

.DESCRIPTION
Thin PowerShell wrapper around:

- codex exec
- codex exec resume

Session continuity is based on the stored thread id only.

Stored session record:
- SessionName
- ThreadId
- LastDirectory
- UpdatedUtc

Directory behavior:
- If SessionName is supplied and Directory is supplied:
  - use Directory
  - store/update LastDirectory
- If SessionName is supplied and Directory is omitted:
  - use stored LastDirectory if present
  - otherwise use current shell directory
- If SessionName is omitted:
  - use Directory if provided
  - otherwise use current shell directory

Important current assumption:
- initial run uses `codex exec --cd <DIR> ...`
- resume uses `codex exec resume ...`
- because `codex exec resume --help` does not show `--cd`,
  this wrapper temporarily changes the PowerShell working directory
  with Push-Location / Pop-Location for resume runs.

Repo check behavior:
- default is relaxed
- wrapper adds --skip-git-repo-check
- use -EnforceRepoCheck to disable that behavior

OutputLastMessage behavior:
- this wrapper does NOT pass --output-last-message to Codex
- when JSON output is available, it extracts the last agent message itself
  and writes it to a local file

.PARAMETER Prompt
Prompt sent to Codex.

.PARAMETER Directory
Optional directory.
If omitted and SessionName is present, LastDirectory is used if available.
Otherwise current shell directory is used.

.PARAMETER SessionName
Optional wrapper-level session name.
Alias: Session

.PARAMETER AllowDangerous
If true, uses --dangerously-bypass-approvals-and-sandbox.

.PARAMETER Sandbox
Sandbox mode for initial exec only when AllowDangerous is false.

.PARAMETER AskForApproval
Reserved for later expansion. Not currently used because your current exec path
is focused on dangerous/full capability mode by default.

.PARAMETER EnforceRepoCheck
If specified, do NOT add --skip-git-repo-check.

.PARAMETER Json
If true, adds --json.
Named sessions force JSON on so thread.started can be captured.

.PARAMETER OutputLastMessage
Optional wrapper-side file path written with the last parsed agent message.
This is NOT forwarded to Codex.

.PARAMETER Color
Color mode for initial exec only.

.PARAMETER Ephemeral
If true, adds --ephemeral.
Default:
- no SessionName => $true
- with SessionName => $false

.PARAMETER Model
Optional model name passed as --model.

.PARAMETER AddDir
Additional writable directories for INITIAL exec only.

.EXAMPLE
Invoke-CodexTask -Prompt "read the dir and output the first file found" -Directory "C:\temp" -Session "foo99"

.EXAMPLE
Invoke-CodexTask -Prompt "read the dir and output the first file found" -Directory "D:\other" -Session "foo99"

.EXAMPLE
Invoke-CodexTask -Prompt "please repeat both filenames" -Session "foo99"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Prompt,

        [Alias('Path')]
        [string]$Directory,

        [Alias('Session')]
        [string]$SessionName,

        [bool]$AllowDangerous = $true,

        [ValidateSet('read-only', 'workspace-write', 'danger-full-access')]
        [string]$Sandbox = 'danger-full-access',

        [ValidateSet('untrusted', 'on-request', 'never')]
        [string]$AskForApproval = 'never',

        [switch]$EnforceRepoCheck,

        [bool]$Json = $true,

        [string]$OutputLastMessage,

        [ValidateSet('always', 'never', 'auto')]
        [string]$Color = 'never',

        [Nullable[bool]]$Ephemeral,

        [string]$Model,

        [string[]]$AddDir
    )

    $codexCmd = Resolve-CodexCommandPath

    $currentDirectory = Resolve-CodexDirectory -Directory ((Get-Location).ProviderPath)
    $directoryProvided = $PSBoundParameters.ContainsKey('Directory')
    $requestedDirectory = $null

    if ($directoryProvided) {
        $requestedDirectory = Resolve-CodexDirectory -Directory $Directory
    }

    if ($null -eq $Ephemeral) {
        $Ephemeral = [string]::IsNullOrWhiteSpace($SessionName)
    }

    $sessionStoreRoot = Join-Path $env:LOCALAPPDATA 'CodexSlots\sessions'
    $sessionStorePath = Join-Path $sessionStoreRoot 'named-sessions.json'

    if (-not (Test-Path -LiteralPath $sessionStoreRoot)) {
        New-Item -ItemType Directory -Path $sessionStoreRoot -Force | Out-Null
    }

    $sessionMap = @{}
    if (Test-Path -LiteralPath $sessionStorePath) {
        try {
            $raw = Get-Content -LiteralPath $sessionStorePath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $obj = $raw | ConvertFrom-Json
                foreach ($p in $obj.PSObject.Properties) {
                    $sessionMap[$p.Name] = $p.Value
                }
            }
        }
        catch {
            $sessionMap = @{}
        }
    }

    $sessionKey = $null
    $existingSession = $null
    $effectiveDirectory = $currentDirectory

    if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
        $sessionKey = ($SessionName.Trim() -replace '\|', '_')

        if ($sessionMap.ContainsKey($sessionKey)) {
            $existingSession = $sessionMap[$sessionKey]
        }

        if ($directoryProvided) {
            $effectiveDirectory = $requestedDirectory
        }
        elseif ($existingSession -and $existingSession.LastDirectory) {
            $effectiveDirectory = [string]$existingSession.LastDirectory
        }
        else {
            $effectiveDirectory = $currentDirectory
        }
    }
    else {
        if ($directoryProvided) {
            $effectiveDirectory = $requestedDirectory
        }
        else {
            $effectiveDirectory = $currentDirectory
        }
    }

    $canResume = [bool](
        $existingSession -and
        $existingSession.ThreadId
    )

    $effectiveJson =
        if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
            $true
        }
        else {
            $Json
        }

    if ([string]::IsNullOrWhiteSpace($OutputLastMessage) -and $effectiveJson) {
        $safeDirName = ([IO.Path]::GetFileName($effectiveDirectory)).Trim()
        if ([string]::IsNullOrWhiteSpace($safeDirName)) {
            $safeDirName = 'workspace'
        }

        $safeDirName = ($safeDirName -replace '[^A-Za-z0-9._-]', '_')

        if ([string]::IsNullOrWhiteSpace($SessionName)) {
            $OutputLastMessage = Join-Path $env:TEMP ("codex-last-message-{0}-{1}.txt" -f $safeDirName, ([Guid]::NewGuid().ToString('N')))
        }
        else {
            $safeSessionFile = ($SessionName -replace '[^A-Za-z0-9._-]', '_')
            $OutputLastMessage = Join-Path $env:TEMP ("codex-last-message-{0}-{1}.txt" -f $safeDirName, $safeSessionFile)
        }
    }

    $cargs = New-Object System.Collections.Generic.List[string]

    if ($canResume) {
        # codex exec resume [OPTIONS] [SESSION_ID] [PROMPT]
        # No --cd here according to the local help you pasted.
        [void]$cargs.Add('exec')
        [void]$cargs.Add('resume')

        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            [void]$cargs.Add('--model')
            [void]$cargs.Add($Model)
        }

        if ($AllowDangerous) {
            [void]$cargs.Add('--dangerously-bypass-approvals-and-sandbox')
        }

        if (-not $EnforceRepoCheck) {
            [void]$cargs.Add('--skip-git-repo-check')
        }

        if ($Ephemeral) {
            [void]$cargs.Add('--ephemeral')
        }

        if ($effectiveJson) {
            [void]$cargs.Add('--json')
        }

        [void]$cargs.Add([string]$existingSession.ThreadId)
        [void]$cargs.Add($Prompt)
    }
    else {
        # codex exec [OPTIONS] [PROMPT]
        [void]$cargs.Add('exec')

        [void]$cargs.Add('--cd')
        [void]$cargs.Add($effectiveDirectory)

        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            [void]$cargs.Add('--model')
            [void]$cargs.Add($Model)
        }

        if ($AllowDangerous) {
            [void]$cargs.Add('--dangerously-bypass-approvals-and-sandbox')
        }
        else {
            [void]$cargs.Add('--sandbox')
            [void]$cargs.Add($Sandbox)
        }

        if (-not $EnforceRepoCheck) {
            [void]$cargs.Add('--skip-git-repo-check')
        }

        foreach ($dir in @($AddDir)) {
            if (-not [string]::IsNullOrWhiteSpace($dir)) {
                [void]$cargs.Add('--add-dir')
                [void]$cargs.Add((Resolve-CodexDirectory -Directory $dir))
            }
        }

        if ($Ephemeral) {
            [void]$cargs.Add('--ephemeral')
        }

        if ($effectiveJson) {
            [void]$cargs.Add('--json')
        }

        if (-not [string]::IsNullOrWhiteSpace($Color)) {
            [void]$cargs.Add('--color')
            [void]$cargs.Add($Color)
        }

        [void]$cargs.Add($Prompt)
    }

    $argArray = $cargs.ToArray()
    $lastAgentMessage = $null

    try {
        if ($canResume) {
            Push-Location -LiteralPath $effectiveDirectory
        }

        if ($effectiveJson) {
            $outputLines = @(& $codexCmd @argArray 2>&1)
            $exitCode = $LASTEXITCODE

            foreach ($line in $outputLines) {
                $text = [string]$line
                Write-Host $text

                try {
                    $evt = $text | ConvertFrom-Json

                    if (-not $canResume -and $evt.type -eq 'thread.started' -and $evt.thread_id -and -not [string]::IsNullOrWhiteSpace($SessionName)) {
                        $sessionMap[$sessionKey] = @{
                            SessionName   = $SessionName
                            ThreadId      = [string]$evt.thread_id
                            LastDirectory = $effectiveDirectory
                            UpdatedUtc    = [DateTime]::UtcNow.ToString('o')
                        }

                        ($sessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sessionStorePath -Encoding UTF8
                        $existingSession = $sessionMap[$sessionKey]
                    }

                    if ($evt.type -eq 'item.completed' -and $evt.item -and $evt.item.type -eq 'agent_message' -and $evt.item.text) {
                        $lastAgentMessage = [string]$evt.item.text
                    }
                }
                catch {
                    # Ignore non-JSON lines.
                }
            }

            if ($canResume -and -not [string]::IsNullOrWhiteSpace($SessionName)) {
                $sessionMap[$sessionKey] = @{
                    SessionName   = $SessionName
                    ThreadId      = [string]$existingSession.ThreadId
                    LastDirectory = $effectiveDirectory
                    UpdatedUtc    = [DateTime]::UtcNow.ToString('o')
                }

                ($sessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sessionStorePath -Encoding UTF8
                $existingSession = $sessionMap[$sessionKey]
            }

            if (-not [string]::IsNullOrWhiteSpace($OutputLastMessage) -and -not [string]::IsNullOrWhiteSpace($lastAgentMessage)) {
                Set-Content -LiteralPath $OutputLastMessage -Value $lastAgentMessage -Encoding UTF8
            }
        }
        else {
            & $codexCmd @argArray
            $exitCode = $LASTEXITCODE

            if ($canResume -and -not [string]::IsNullOrWhiteSpace($SessionName)) {
                $sessionMap[$sessionKey] = @{
                    SessionName   = $SessionName
                    ThreadId      = [string]$existingSession.ThreadId
                    LastDirectory = $effectiveDirectory
                    UpdatedUtc    = [DateTime]::UtcNow.ToString('o')
                }

                ($sessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sessionStorePath -Encoding UTF8
                $existingSession = $sessionMap[$sessionKey]
            }
        }
    }
    finally {
        if ($canResume) {
            Pop-Location
        }
    }

    if ($exitCode -ne 0) {
        throw "codex command failed with exit code $exitCode."
    }

    [pscustomobject]@{
        CommandPath       = $codexCmd
        Directory         = $effectiveDirectory
        SessionName       = $SessionName
        ThreadId          = if ($existingSession) { $existingSession.ThreadId } else { $null }
        Prompt            = $Prompt
        AllowDangerous    = [bool]$AllowDangerous
        Json              = [bool]$effectiveJson
        Ephemeral         = [bool]$Ephemeral
        OutputLastMessage = $OutputLastMessage
        LastAgentMessage  = $lastAgentMessage
        ExitCode          = $exitCode
        Resumed           = $canResume
        EffectiveArgs     = $argArray
    }
}

<#

# Import the module into the current PowerShell session
Import-Module Eigenverft.Manifested.Codex -Force

# Show overall manager/runtime state
Get-CodexState

# List all slots
Get-CodexSlots

# Initialize the default slot
Initialize-CodexSlot

# Initialize a named slot
Initialize-CodexSlot -Name experimental

# Refresh Node runtime and force Codex CLI reinstall in a slot
Initialize-CodexSlot -Name experimental -RefreshNode -ForceCodex

# Activate a slot
Use-CodexSlot -Name default

# Verify a slot
Test-CodexSlot -Name default

# Remove a slot
Remove-CodexSlot -Name experimental -Force

# Show manager and slot layout paths
Get-CodexManagerLayout
Get-CodexSlotLayout -Name default

# Resolve the Codex command currently on PATH
Resolve-CodexCommandPath

# Resolve a working directory
Resolve-CodexDirectory -Directory 'C:\temp'

# Show detected Node flavor
Get-CodexNodeFlavor

# Show the latest cached Node zip
Get-LatestCachedNodeZip

# Ensure a Node zip is present in cache
Ensure-CodexNodeZip

# Force refresh the cached Node zip
Ensure-CodexNodeZip -RefreshNode

# Ensure the managed Node runtime is extracted and ready
Ensure-CodexNodeRuntime

# Force refresh and re-extract the managed Node runtime
Ensure-CodexNodeRuntime -RefreshNode

# Inspect the persisted manager state
Get-CodexManagerState

# Inspect slot metadata
Get-CodexSlotMetadata -Name default

# List all stored named sessions
Get-CodexSession

# Get one stored named session
Get-CodexSession -SessionName foo99

# Change the remembered last directory for a stored session
Set-CodexSessionDirectory -SessionName foo99 -Directory 'C:\temp'

# Remove one stored session
Remove-CodexSession -SessionName foo99 -Force

# Clear all stored sessions
Clear-CodexSessions -Force

# Run a one-shot task in the current directory
Invoke-CodexTask -Prompt "read the dir and output the first file found"

# Run a one-shot task in a specific directory
Invoke-CodexTask -Prompt "read the dir and output the first file found" -Directory 'C:\temp'

# Start or continue a named session in a specific directory
Invoke-CodexTask -Prompt "read the dir and output the first file found" -Directory 'C:\temp' -SessionName 'foo99'

# Continue a named session without respecifying the directory
Invoke-CodexTask -Prompt "please repeat both filenames" -SessionName 'foo99'

# Move a named session to a new remembered directory
Invoke-CodexTask -Prompt "read the dir and output the first file found" -Directory 'D:\project' -SessionName 'foo99'

# Continue again from the remembered directory
Invoke-CodexTask -Prompt "please give me the last filename in that dir" -SessionName 'foo99'

# Enforce git repo check instead of skipping it
Invoke-CodexTask -Prompt "inspect the repo and summarize status" -Directory 'D:\project' -SessionName 'repo1' -EnforceRepoCheck

# Use a specific model
Invoke-CodexTask -Prompt "read todo.txt and execute one task" -Directory 'D:\project' -SessionName 'todo1' -Model 'gpt-5-codex'

# Run in non-dangerous mode for the initial exec path
Invoke-CodexTask -Prompt "inspect the repository and summarize it" -Directory 'D:\project' -AllowDangerous:$false -Sandbox workspace-write

# Explicit ephemeral one-shot run
Invoke-CodexTask -Prompt "summarize the files in this folder" -Directory 'C:\temp' -Ephemeral $true

# Add additional writable directories for the initial exec path
Invoke-CodexTask -Prompt "work across both directories" -Directory 'D:\project' -AddDir 'D:\shared','D:\artifacts'

# Capture the wrapper-side last message file and parsed last agent message
$result = Invoke-CodexTask -Prompt "read the dir and output the first file found" -Directory 'C:\temp' -SessionName 'foo99'
$result.OutputLastMessage
$result.LastAgentMessage

#>
