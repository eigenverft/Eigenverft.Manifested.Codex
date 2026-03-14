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

function Get-CodexVersion {
    [CmdletBinding()]
    param()

    $moduleName = 'Eigenverft.Manifested.Codex'
    $moduleInfo = @(Get-Module -ListAvailable -Name $moduleName | Sort-Object -Descending -Property Version | Select-Object -First 1)

    if (-not $moduleInfo) {
        $loadedModule = @(Get-Module -Name $moduleName | Sort-Object -Descending -Property Version | Select-Object -First 1)
        if ($loadedModule) {
            $moduleInfo = $loadedModule
        }
        elseif ($ExecutionContext.SessionState.Module -and $ExecutionContext.SessionState.Module.Name -eq $moduleName) {
            $moduleInfo = @($ExecutionContext.SessionState.Module)
        }
    }

    if (-not $moduleInfo) {
        $manifestPath = Join-Path $PSScriptRoot ($moduleName + '.psd1')
        if (Test-Path -LiteralPath $manifestPath) {
            $manifestData = Import-PowerShellDataFile -Path $manifestPath
            if ($manifestData -and $manifestData.ModuleVersion) {
                return ('{0} {1}' -f $moduleName, $manifestData.ModuleVersion.ToString())
            }
        }

        throw "Could not resolve the installed or loaded version of module '$moduleName'."
    }

    return ('{0} {1}' -f $moduleName, $moduleInfo[0].Version.ToString())
}
