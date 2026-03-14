<#
Default PSGallery bootstrapper for installing/importing Eigenverft.Manifested.Codex,
then opening a new Windows PowerShell console and invoking the default follow-up command.

Current defaults:

$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Codex'
$c='Import-Module Eigenverft.Manifested.Codex -Force;Get-CodexVersion'

Use via

iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Codex/refs/heads/<branch>/iwr/bootstrapper.ps1 | iex
#>

$c='Import-Module Eigenverft.Manifested.Codex -Force;Get-CodexVersion';$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Codex';$s='CurrentUser';$g='PSGallery';$u='https://www.powershellgallery.com/api/v2';if($PSVersionTable.PSVersion.Major-ne5){return};try{Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted -Force}catch{};try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};[System.Net.WebRequest]::DefaultWebProxy=[System.Net.WebRequest]::GetSystemWebProxy();if([System.Net.WebRequest]::DefaultWebProxy){[System.Net.WebRequest]::DefaultWebProxy.Credentials=[System.Net.CredentialCache]::DefaultNetworkCredentials};$v=[version]'2.8.5.201';Install-PackageProvider NuGet -MinimumVersion $v -Scope $s -Force -ForceBootstrap|Out-Null;try{Set-PSRepository $g -InstallationPolicy Trusted -ea Stop}catch{Register-PSRepository $g -SourceLocation $u -ScriptSourceLocation $u -InstallationPolicy Trusted -ea Stop};Find-Module $i -Repository $g|select Name,Version|?{-not(Get-Module -ListAvailable $_.Name|sort Version -desc|select -f 1|? Version -eq $_.Version)}|%{Install-Module $_.Name -RequiredVersion $_.Version -Repository $g -Scope $s -Force -AllowClobber;try{Remove-Module $_.Name -ea 0}catch{};Import-Module $_.Name -MinimumVersion $_.Version -Force};Start-Process cmd "/c start `"`" powershell -NoExit -Command `"$c;`"";exit
