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
Get-NodeFlavor

# Show the latest cached Node zip
Get-LatestCachedNodeZip

# Ensure a Node zip is present in cache
Ensure-NodeZip

# Force refresh the cached Node zip
Ensure-NodeZip -RefreshNode

# Ensure the managed Node runtime is extracted and ready
Ensure-NodeRuntime

# Force refresh and re-extract the managed Node runtime
Ensure-NodeRuntime -RefreshNode

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

