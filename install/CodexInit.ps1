Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$install = @('PowerShellGet', 'PackageManagement', 'Eigenverft.Manifested.Codex')
$scope = 'CurrentUser'

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw 'PowerShell 5.1 or newer is required.'
}

try {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted -Force
}
catch {
    # Best effort only. This can fail under managed policy.
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
    # Best effort only. Older hosts may already be configured appropriately.
}

[System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
if ([System.Net.WebRequest]::DefaultWebProxy) {
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
}

$minNuget = [Version]'2.8.5.201'
Install-PackageProvider -Name NuGet -MinimumVersion $minNuget -Scope $scope -Force -ForceBootstrap | Out-Null

try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
}
catch {
    Register-PSRepository -Name PSGallery -SourceLocation 'https://www.powershellgallery.com/api/v2' -ScriptSourceLocation 'https://www.powershellgallery.com/api/v2' -InstallationPolicy Trusted -ErrorAction Stop
}

Find-Module -Name $install -Repository PSGallery |
    Select-Object Name, Version |
    Where-Object {
        -not (
            Get-Module -ListAvailable -Name $_.Name |
                Sort-Object Version -Descending |
                Select-Object -First 1 |
                Where-Object Version -eq $_.Version
        )
    } |
    ForEach-Object {
        Install-Module -Name $_.Name -RequiredVersion $_.Version -Repository PSGallery -Scope $scope -Force -AllowClobber
        try {
            Remove-Module -Name $_.Name -ErrorAction SilentlyContinue
        }
        catch {
        }

        Import-Module -Name $_.Name -MinimumVersion $_.Version -Force
    }

Write-Host 'Setup complete. Start a new console session, then run Initialize-CodexSlot to provision the default Codex slot.' -ForegroundColor Green

<#
powershell -NoProfile -ExecutionPolicy Bypass -File .\install\CodexInit.ps1
#>
