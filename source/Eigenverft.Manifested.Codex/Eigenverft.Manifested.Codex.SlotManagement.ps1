<#
    Eigenverft.Manifested.Codex.SlotManagement
#>

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

    $nodeHome = Get-ManagedNodeHome -Version $meta.NodeVersion -Flavor $meta.NodeFlavor -LocalRoot $LocalRoot
    if (-not (Test-ManagedNodeHome -NodeHome $nodeHome)) {
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

    $runtime = Ensure-NodeRuntime -RefreshNode:$RefreshNode -LocalRoot $LocalRoot

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
        $nodeHome = Get-ManagedNodeHome -Version $meta.NodeVersion -Flavor $meta.NodeFlavor -LocalRoot $LocalRoot
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
        ReadyToRun          = ($slotInstalled -and (Test-ManagedNodeHome -NodeHome $nodeHome))
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
    $flavor = Get-NodeFlavor
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
        $activeNodeHome = Get-ManagedNodeHome -Version $manager.NodeVersion -Flavor $manager.NodeFlavor -LocalRoot $LocalRoot
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
