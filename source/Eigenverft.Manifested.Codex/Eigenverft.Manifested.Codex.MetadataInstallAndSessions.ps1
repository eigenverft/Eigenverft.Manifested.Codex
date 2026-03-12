<#
    Eigenverft.Manifested.Codex.MetadataInstallAndSessions
#>

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
