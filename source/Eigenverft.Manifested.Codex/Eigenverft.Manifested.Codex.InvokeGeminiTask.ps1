<#
    Eigenverft.Manifested.Codex.InvokeGeminiTask
#>

function Get-GeminiSessionStorePath {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-CodexLocalRoot)
    )

    return (Join-Path (Join-Path $LocalRoot 'sessions') 'named-gemini-sessions.json')
}

function Get-GeminiSessionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    return ($SessionName.Trim() -replace '\|', '_')
}

function Read-GeminiSessionMap {
    [CmdletBinding()]
    param(
        [string]$SessionStorePath = (Get-GeminiSessionStorePath)
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
        throw "Failed to read Gemini session store: $SessionStorePath"
    }

    return $sessionMap
}

function Write-GeminiSessionMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SessionMap,

        [string]$SessionStorePath = (Get-GeminiSessionStorePath)
    )

    $sessionStoreRoot = Split-Path -Parent $SessionStorePath
    if (-not (Test-Path -LiteralPath $sessionStoreRoot)) {
        New-Item -ItemType Directory -Path $sessionStoreRoot -Force | Out-Null
    }

    ($SessionMap | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $SessionStorePath -Encoding UTF8
}

function Resolve-GeminiCommandPath {
    [CmdletBinding()]
    param()

    foreach ($candidate in @('gemini.cmd', 'gemini', 'gemini.ps1')) {
        $resolvedGemini = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $resolvedGemini) {
            continue
        }

        if ($resolvedGemini.PSObject.Properties['Path'] -and $resolvedGemini.Path) {
            return $resolvedGemini.Path
        }

        return $resolvedGemini.Source
    }

    throw 'gemini was not found on PATH. Install the Gemini CLI or add it to PATH before using Invoke-GeminiTask.'
}

function ConvertFrom-GeminiJsonLine {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    $text = [string]$Line

    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }

    try {
        return ($text | ConvertFrom-Json -Depth 100)
    }
    catch {
        return $null
    }
}

function Convert-GeminiProcessOutputToLines {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }

    $lines = [regex]::Split($Text, "\r?\n")

    if ($lines.Count -gt 0 -and [string]::IsNullOrEmpty($lines[$lines.Count - 1])) {
        $lines = @($lines | Select-Object -First ($lines.Count - 1))
    }

    return @($lines)
}

function Get-GeminiInvocationLineRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Invocation
    )

    $records =
        foreach ($sourceName in @('StdErrLines', 'StdOutLines')) {
            foreach ($line in @($Invocation.$sourceName)) {
                $text = [string]$line

                [pscustomobject]@{
                    Source = $sourceName
                    Line   = $text
                    Event  = ConvertFrom-GeminiJsonLine -Line $text
                }
            }
        }

    return @($records)
}

function ConvertTo-GeminiProcessArgument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value.Length -eq 0) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $pendingBackslashes = 0

    foreach ($char in $Value.ToCharArray()) {
        if ($char -eq '\') {
            $pendingBackslashes++
            continue
        }

        if ($char -eq '"') {
            if ($pendingBackslashes -gt 0) {
                [void]$builder.Append(('\' * ($pendingBackslashes * 2)))
                $pendingBackslashes = 0
            }

            [void]$builder.Append('\"')
            continue
        }

        if ($pendingBackslashes -gt 0) {
            [void]$builder.Append(('\' * $pendingBackslashes))
            $pendingBackslashes = 0
        }

        [void]$builder.Append($char)
    }

    if ($pendingBackslashes -gt 0) {
        [void]$builder.Append(('\' * ($pendingBackslashes * 2)))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-GeminiProcessArgumentString {
    [CmdletBinding()]
    param(
        [string[]]$Arguments
    )

    return ((@($Arguments) | ForEach-Object { ConvertTo-GeminiProcessArgument -Value $_ }) -join ' ')
}

function Invoke-GeminiProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GeminiCommandPath,

        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $stdoutPath = Join-Path $env:TEMP ("gemini-stdout-{0}.log" -f ([Guid]::NewGuid().ToString('N')))
    $stderrPath = Join-Path $env:TEMP ("gemini-stderr-{0}.log" -f ([Guid]::NewGuid().ToString('N')))

    $argumentString = ConvertTo-GeminiProcessArgumentString -Arguments $Arguments

    try {
        $process = Start-Process `
            -FilePath $GeminiCommandPath `
            -ArgumentList $argumentString `
            -WorkingDirectory $Directory `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -Wait `
            -PassThru `
            -NoNewWindow

        $stdoutRaw = ''
        $stderrRaw = ''

        if (Test-Path -LiteralPath $stdoutPath) {
            $stdoutRaw = Get-Content -LiteralPath $stdoutPath -Raw
        }

        if (Test-Path -LiteralPath $stderrPath) {
            $stderrRaw = Get-Content -LiteralPath $stderrPath -Raw
        }

        [pscustomobject]@{
            ExitCode    = [int]$process.ExitCode
            StdOutRaw   = [string]$stdoutRaw
            StdErrRaw   = [string]$stderrRaw
            StdOutLines = @(Convert-GeminiProcessOutputToLines -Text $stdoutRaw)
            StdErrLines = @(Convert-GeminiProcessOutputToLines -Text $stderrRaw)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-GeminiSessionListing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GeminiCommandPath,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $invocation = Invoke-GeminiProcess -GeminiCommandPath $GeminiCommandPath -Arguments @('--list-sessions') -Directory $Directory

    $sessionIds = New-Object System.Collections.Generic.List[string]

    foreach ($record in @(Get-GeminiInvocationLineRecords -Invocation $invocation)) {
        $text = [string]$record.Line
        $match = [regex]::Match($text, '\[(?<id>[^\]]+)\]')

        if ($match.Success) {
            [void]$sessionIds.Add($match.Groups['id'].Value)
        }
    }

    [pscustomobject]@{
        Succeeded  = ($invocation.ExitCode -eq 0)
        ExitCode   = $invocation.ExitCode
        SessionIds = @($sessionIds | Select-Object -Unique)
        Lines      = @((Get-GeminiInvocationLineRecords -Invocation $invocation) | ForEach-Object { [string]$_.Line })
    }
}

function Test-GeminiListedSessionId {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$StoredSessionId,

        [string[]]$ListedSessionIds
    )

    if ([string]::IsNullOrWhiteSpace($StoredSessionId)) {
        return $false
    }

    foreach ($listedSessionId in @($ListedSessionIds)) {
        $candidate = [string]$listedSessionId

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if ($StoredSessionId.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($StoredSessionId.StartsWith($candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($candidate.StartsWith($StoredSessionId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Complete-GeminiAssistantMessageCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Text.StringBuilder]$CurrentMessageBuilder,

        [Parameter(Mandatory = $true)]
        [ref]$LastAgentMessage
    )

    if ($CurrentMessageBuilder.Length -le 0) {
        return
    }

    $LastAgentMessage.Value = $CurrentMessageBuilder.ToString()
    [void]$CurrentMessageBuilder.Clear()
}

function Invoke-GeminiTask {
<#
.SYNOPSIS
Runs a Gemini non-interactive task and maintains wrapper-level named session state.

.DESCRIPTION
Thin PowerShell wrapper around Gemini CLI headless mode.

Wrapper-managed named sessions store:
- SessionName
- SessionId
- LastDirectory
- UpdatedUtc

Gemini-native sessions remain project-scoped.
This wrapper keeps a friendly session name that points at the last observed Gemini session id.

For named sessions, the wrapper uses `--output-format stream-json`
so it can capture the Gemini session id from the `init` event.

Before resuming a named session, the wrapper checks `gemini --list-sessions`
in the effective directory. If the stored Gemini session is no longer listed,
the wrapper starts a fresh Gemini session instead of forcing a stale resume id.
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

        [bool]$Json = $true,

        [string]$OutputLastMessage,

        [string]$Model,

        [string[]]$AddDir
    )

    $geminiCmd = Resolve-GeminiCommandPath

    $currentDirectory = Resolve-CodexDirectory -Directory ((Get-Location).ProviderPath)
    $directoryProvided = $PSBoundParameters.ContainsKey('Directory')
    $requestedDirectory = $null

    if ($directoryProvided) {
        $requestedDirectory = Resolve-CodexDirectory -Directory $Directory
    }

    $sessionStorePath = Get-GeminiSessionStorePath
    $sessionStoreRoot = Split-Path -Parent $sessionStorePath

    if (-not (Test-Path -LiteralPath $sessionStoreRoot)) {
        New-Item -ItemType Directory -Path $sessionStoreRoot -Force | Out-Null
    }

    $sessionMap =
        if (Test-Path -LiteralPath $sessionStorePath) {
            Read-GeminiSessionMap -SessionStorePath $sessionStorePath
        }
        else {
            @{}
        }

    $sessionKey = $null
    $existingSession = $null
    $effectiveDirectory = $currentDirectory

    if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
        $sessionKey = Get-GeminiSessionKey -SessionName $SessionName

        if ($sessionMap.ContainsKey($sessionKey)) {
            $existingSession = $sessionMap[$sessionKey]
        }

        if ($directoryProvided) {
            $effectiveDirectory = $requestedDirectory
        }
        elseif ($existingSession -and $existingSession.LastDirectory) {
            $effectiveDirectory = Resolve-CodexDirectory -Directory ([string]$existingSession.LastDirectory)
        }
        else {
            $effectiveDirectory = $currentDirectory
        }
    }
    elseif ($directoryProvided) {
        $effectiveDirectory = $requestedDirectory
    }

    $preRunListing = $null

    if ($existingSession -and $existingSession.SessionId) {
        $preRunListing = Get-GeminiSessionListing -GeminiCommandPath $geminiCmd -Directory $effectiveDirectory

        if ($preRunListing.Succeeded) {
            $storedSessionId = [string]$existingSession.SessionId

            if (-not (Test-GeminiListedSessionId -StoredSessionId $storedSessionId -ListedSessionIds $preRunListing.SessionIds)) {
                $existingSession = $null
            }
        }
    }

    $canResume = [bool](
        $existingSession -and
        $existingSession.SessionId
    )

    $effectiveOutputFormat =
        if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
            'stream-json'
        }
        elseif ($Json) {
            'json'
        }
        else {
            'text'
        }

    if ([string]::IsNullOrWhiteSpace($OutputLastMessage) -and $effectiveOutputFormat -ne 'text') {
        $safeDirName = ([IO.Path]::GetFileName($effectiveDirectory)).Trim()
        if ([string]::IsNullOrWhiteSpace($safeDirName)) {
            $safeDirName = 'workspace'
        }

        $safeDirName = ($safeDirName -replace '[^A-Za-z0-9._-]', '_')

        if ([string]::IsNullOrWhiteSpace($SessionName)) {
            $OutputLastMessage = Join-Path $env:TEMP ("gemini-last-message-{0}-{1}.txt" -f $safeDirName, ([Guid]::NewGuid().ToString('N')))
        }
        else {
            $safeSessionFile = ($SessionName -replace '[^A-Za-z0-9._-]', '_')
            $OutputLastMessage = Join-Path $env:TEMP ("gemini-last-message-{0}-{1}.txt" -f $safeDirName, $safeSessionFile)
        }
    }

    $cargs = New-Object System.Collections.Generic.List[string]

    if ($canResume) {
        [void]$cargs.Add('--resume')
        [void]$cargs.Add([string]$existingSession.SessionId)
    }

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        [void]$cargs.Add('--model')
        [void]$cargs.Add($Model)
    }

    if ($AllowDangerous) {
        [void]$cargs.Add('--approval-mode')
        [void]$cargs.Add('yolo')
    }
    else {
        [void]$cargs.Add('--sandbox')
    }

    foreach ($dir in @($AddDir)) {
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            [void]$cargs.Add('--include-directories')
            [void]$cargs.Add((Resolve-CodexDirectory -Directory $dir))
        }
    }

    [void]$cargs.Add('--output-format')
    [void]$cargs.Add($effectiveOutputFormat)
    [void]$cargs.Add('-p')
    [void]$cargs.Add($Prompt)

    $argArray = $cargs.ToArray()
    $observedSessionId = $null
    $lastAgentMessage = $null
    $structuredErrorMessage = $null
    $exitCode = 0
    $currentAssistantMessageBuilder = New-Object System.Text.StringBuilder

    $invocation = Invoke-GeminiProcess -GeminiCommandPath $geminiCmd -Arguments $argArray -Directory $effectiveDirectory
    $exitCode = $invocation.ExitCode

    if ($effectiveOutputFormat -eq 'stream-json') {
        $streamJsonRecords = @(Get-GeminiInvocationLineRecords -Invocation $invocation)

        foreach ($record in $streamJsonRecords) {
            Write-Host ([string]$record.Line)
        }

        foreach ($record in $streamJsonRecords) {
            $evt = $record.Event

            if (-not $evt) {
                Complete-GeminiAssistantMessageCapture -CurrentMessageBuilder $currentAssistantMessageBuilder -LastAgentMessage ([ref]$lastAgentMessage)
                continue
            }

            if (
                $evt.type -eq 'init' -and
                $evt.PSObject.Properties.Match('session_id').Count -gt 0 -and
                $evt.session_id
            ) {
                $observedSessionId = [string]$evt.session_id

                if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
                    $sessionMap[$sessionKey] = @{
                        SessionName   = $SessionName
                        SessionId     = $observedSessionId
                        LastDirectory = $effectiveDirectory
                        UpdatedUtc    = [DateTime]::UtcNow.ToString('o')
                    }

                    Write-GeminiSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath
                    $existingSession = $sessionMap[$sessionKey]
                }
            }

            $isAssistantMessage = [bool](
                $evt.type -eq 'message' -and
                $evt.PSObject.Properties.Match('role').Count -gt 0 -and
                $evt.role -eq 'assistant' -and
                $evt.PSObject.Properties.Match('content').Count -gt 0 -and
                $evt.content
            )

            if ($isAssistantMessage) {
                $isDeltaMessage =
                    [bool](
                        $evt.PSObject.Properties.Match('delta').Count -gt 0 -and
                        [bool]$evt.delta
                    )

                if (-not $isDeltaMessage) {
                    Complete-GeminiAssistantMessageCapture -CurrentMessageBuilder $currentAssistantMessageBuilder -LastAgentMessage ([ref]$lastAgentMessage)
                }

                [void]$currentAssistantMessageBuilder.Append([string]$evt.content)
                continue
            }

            Complete-GeminiAssistantMessageCapture -CurrentMessageBuilder $currentAssistantMessageBuilder -LastAgentMessage ([ref]$lastAgentMessage)

            if (
                $evt.type -eq 'error' -and
                $evt.PSObject.Properties.Match('message').Count -gt 0 -and
                $evt.message
            ) {
                $structuredErrorMessage = [string]$evt.message
            }

            if (
                $evt.type -eq 'result' -and
                $evt.PSObject.Properties.Match('error').Count -gt 0 -and
                $evt.error -and
                $evt.error.message
            ) {
                $structuredErrorMessage = [string]$evt.error.message
            }
        }

        Complete-GeminiAssistantMessageCapture -CurrentMessageBuilder $currentAssistantMessageBuilder -LastAgentMessage ([ref]$lastAgentMessage)
    }
    elseif ($effectiveOutputFormat -eq 'json') {
        foreach ($line in @($invocation.StdErrLines)) {
            Write-Host ([string]$line)
        }

        $rawStructuredOutput =
            if (-not [string]::IsNullOrWhiteSpace($invocation.StdOutRaw)) {
                [string]$invocation.StdOutRaw
            }
            else {
                [string]$invocation.StdErrRaw
            }

        if (-not [string]::IsNullOrWhiteSpace($rawStructuredOutput)) {
            Write-Host ($rawStructuredOutput.TrimEnd("`r", "`n"))

            try {
                $payload = $rawStructuredOutput | ConvertFrom-Json -Depth 100

                if ($payload.PSObject.Properties['session_id'] -and $payload.session_id) {
                    $observedSessionId = [string]$payload.session_id
                }

                if ($payload.PSObject.Properties['response'] -and $payload.response) {
                    $lastAgentMessage = [string]$payload.response
                }

                if ($payload.PSObject.Properties['error'] -and $payload.error -and $payload.error.message) {
                    $structuredErrorMessage = [string]$payload.error.message
                }
            }
            catch {
                # Ignore invalid JSON payloads.
            }
        }
    }
    else {
        foreach ($line in @($invocation.StdErrLines + $invocation.StdOutLines)) {
            Write-Host ([string]$line)
        }
    }

    if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($SessionName)) {
        $finalSessionId =
            if (-not [string]::IsNullOrWhiteSpace($observedSessionId)) {
                $observedSessionId
            }
            elseif ($existingSession -and $existingSession.SessionId) {
                [string]$existingSession.SessionId
            }
            else {
                $null
            }

        if (-not [string]::IsNullOrWhiteSpace($finalSessionId)) {
            $sessionMap[$sessionKey] = @{
                SessionName   = $SessionName
                SessionId     = $finalSessionId
                LastDirectory = $effectiveDirectory
                UpdatedUtc    = [DateTime]::UtcNow.ToString('o')
            }

            Write-GeminiSessionMap -SessionMap $sessionMap -SessionStorePath $sessionStorePath
            $existingSession = $sessionMap[$sessionKey]
        }

        [void](Get-GeminiSessionListing -GeminiCommandPath $geminiCmd -Directory $effectiveDirectory)
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputLastMessage) -and -not [string]::IsNullOrWhiteSpace($lastAgentMessage)) {
        Set-Content -LiteralPath $OutputLastMessage -Value $lastAgentMessage -Encoding UTF8
    }

    if ($exitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($structuredErrorMessage)) {
            throw "gemini command failed with exit code $exitCode. $structuredErrorMessage"
        }

        throw "gemini command failed with exit code $exitCode."
    }

    [pscustomobject]@{
        CommandPath       = $geminiCmd
        Directory         = $effectiveDirectory
        SessionName       = $SessionName
        SessionId         = if ($existingSession) { $existingSession.SessionId } else { $observedSessionId }
        Prompt            = $Prompt
        AllowDangerous    = [bool]$AllowDangerous
        Json              = [bool]($effectiveOutputFormat -ne 'text')
        OutputLastMessage = $OutputLastMessage
        LastAgentMessage  = $lastAgentMessage
        ExitCode          = $exitCode
        Resumed           = $canResume
        EffectiveArgs     = $argArray
    }
}
