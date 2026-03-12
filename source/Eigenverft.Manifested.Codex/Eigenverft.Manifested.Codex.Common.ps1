<#
    Eigenverft.Manifested.Codex.Common
#>

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

function ConvertTo-NodeVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    return [version]($VersionText -replace '^v', '')
}
