<#
    Eigenverft.Manifested.Codex.MetadataInstallAndSessions
#>

function Get-CodexLocalRoot {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Join-Path $env:LOCALAPPDATA 'CodexSlots')
    )

    return [System.IO.Path]::GetFullPath($LocalRoot)
}

function Get-CodexSessionStorePath {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-CodexLocalRoot)
    )

    return (Join-Path (Join-Path $LocalRoot 'sessions') 'named-sessions.json')
}

function Get-CodexSessionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    return ($SessionName.Trim() -replace '\|', '_')
}

function Read-CodexSessionMap {
    [CmdletBinding()]
    param(
        [string]$SessionStorePath = (Get-CodexSessionStorePath)
    )

    $sessionMap = @{}
    if (-not (Test-Path -LiteralPath $SessionStorePath)) {
        return $sessionMap
    }

    try {
        $raw = Get-Content -LiteralPath $SessionStorePath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $obj = $raw | ConvertFrom-Json
            foreach ($property in $obj.PSObject.Properties) {
                $sessionMap[$property.Name] = $property.Value
            }
        }
    }
    catch {
        throw "Failed to read session store: $SessionStorePath"
    }

    return $sessionMap
}

function Write-CodexSessionMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SessionMap,

        [string]$SessionStorePath = (Get-CodexSessionStorePath)
    )

    $sessionStoreRoot = Split-Path -Parent $SessionStorePath
    if (-not (Test-Path -LiteralPath $sessionStoreRoot)) {
        New-Item -ItemType Directory -Path $sessionStoreRoot -Force | Out-Null
    }

    ($SessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $SessionStorePath -Encoding UTF8
}

function Resolve-CodexCommandPath {
    [CmdletBinding()]
    param()

    $resolvedCodex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $resolvedCodex) {
        $resolvedCodex = Get-Command codex.cmd -ErrorAction SilentlyContinue
    }

    if (-not $resolvedCodex) {
        throw 'codex was not found on PATH. Install the Codex CLI or add it to PATH before using Eigenverft.Manifested.Codex.'
    }

    if ($resolvedCodex.PSObject.Properties['Path'] -and $resolvedCodex.Path) {
        return $resolvedCodex.Path
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

function Get-CodexState {
    [CmdletBinding()]
    param()

    $localRoot = Get-CodexLocalRoot
    $sessionStorePath = Get-CodexSessionStorePath -LocalRoot $localRoot
    $sessionStoreExists = Test-Path -LiteralPath $sessionStorePath
    $sessionCount = 0

    if ($sessionStoreExists) {
        $sessionCount = @((Read-CodexSessionMap -SessionStorePath $sessionStorePath).Keys).Count
    }

    $codexCommandPath = $null
    try {
        $codexCommandPath = Resolve-CodexCommandPath
    }
    catch {
        $codexCommandPath = $null
    }

    [pscustomobject]@{
        LocalRoot          = $localRoot
        SessionStorePath   = $sessionStorePath
        SessionStoreExists = $sessionStoreExists
        SessionCount       = $sessionCount
        CodexCommandPath   = $codexCommandPath
        CodexAvailable     = [bool]$codexCommandPath
        ReadyToRun         = [bool]$codexCommandPath
    }
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
#>
    [CmdletBinding()]
    param(
        [Alias('Session')]
        [string]$SessionName
    )

    $sessionStorePath = Get-CodexSessionStorePath
    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        if ($PSBoundParameters.ContainsKey('SessionName')) {
            return $null
        }

        return @()
    }

    $sessionMap = Read-CodexSessionMap -SessionStorePath $sessionStorePath

    if ($PSBoundParameters.ContainsKey('SessionName')) {
        $sessionKey = Get-CodexSessionKey -SessionName $SessionName

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

    $sessionStorePath = Get-CodexSessionStorePath
    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        return $false
    }

    $sessionMap = Read-CodexSessionMap -SessionStorePath $sessionStorePath
    $sessionKey = Get-CodexSessionKey -SessionName $SessionName

    if (-not $sessionMap.ContainsKey($sessionKey)) {
        return $false
    }

    if ($PSCmdlet.ShouldProcess($sessionKey, 'Remove stored Codex session')) {
        [void]$sessionMap.Remove($sessionKey)
        Write-CodexSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath
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
#>
    [CmdletBinding()]
    param(
        [Alias('Session')]
        [Parameter(Mandatory = $true)]
        [string]$SessionName,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $sessionStorePath = Get-CodexSessionStorePath
    $resolvedDirectory = Resolve-CodexDirectory -Directory $Directory

    if (-not (Test-Path -LiteralPath $sessionStorePath)) {
        throw "Session store was not found: $sessionStorePath"
    }

    $sessionMap = Read-CodexSessionMap -SessionStorePath $sessionStorePath
    $sessionKey = Get-CodexSessionKey -SessionName $SessionName

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

    Write-CodexSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath

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
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Force
    )

    if (-not $Force) {
        throw 'Pass -Force to clear all stored sessions.'
    }

    $sessionStorePath = Get-CodexSessionStorePath
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

    $sessionStorePath = Get-CodexSessionStorePath
    $sessionStoreRoot = Split-Path -Parent $sessionStorePath

    if (-not (Test-Path -LiteralPath $sessionStoreRoot)) {
        New-Item -ItemType Directory -Path $sessionStoreRoot -Force | Out-Null
    }

    $sessionMap = @{}
    if (Test-Path -LiteralPath $sessionStorePath) {
        try {
            $raw = Get-Content -LiteralPath $sessionStorePath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $obj = $raw | ConvertFrom-Json
                foreach ($property in $obj.PSObject.Properties) {
                    $sessionMap[$property.Name] = $property.Value
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
        $sessionKey = Get-CodexSessionKey -SessionName $SessionName

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
    elseif ($directoryProvided) {
        $effectiveDirectory = $requestedDirectory
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

                        Write-CodexSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath
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

                Write-CodexSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath
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

                Write-CodexSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath
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
