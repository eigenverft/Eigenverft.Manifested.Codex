# Eigenverft.Manifested.Codex

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Codex?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Codex)
[![PowerShell Gallery Platform Support](https://img.shields.io/powershellgallery/p/Eigenverft.Manifested.Codex?logo=windows)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Codex)
[![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Codex?logo=mit)](LICENSE)

Windows-focused PowerShell module for installing, managing, and invoking isolated OpenAI Codex CLI slots with a managed Node.js runtime, persisted session state, and task execution helpers.

## What it does

- Installs the Codex CLI into named slots under `$HOME\.codex-slots`
- Downloads and verifies a managed Node.js LTS runtime under `%LOCALAPPDATA%\CodexSlots`
- Switches the active slot by updating `PATH` for the current process and user scope
- Persists slot metadata and wrapper-side named session state
- Adds a thin PowerShell wrapper around `codex exec` and `codex exec resume`

## Requirements

- Windows x64 or Windows ARM64
- PowerShell 5.1 or newer
- Network access to PowerShell Gallery and `nodejs.org` for first-time setup
- Codex CLI access/authentication as required by `@openai/codex`

## Installation

### Install from PowerShell Gallery

```powershell
Install-Module -Name Eigenverft.Manifested.Codex -Repository PSGallery -Scope CurrentUser -Force
Import-Module Eigenverft.Manifested.Codex -Force
Initialize-CodexSlot
```

### Bootstrap from this repository

Use the included bootstrap script if the machine still needs `PowerShellGet` and `PackageManagement` prepared for the current user:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install\CodexInit.ps1
```

Then start a new console session and run:

```powershell
Import-Module Eigenverft.Manifested.Codex -Force
Initialize-CodexSlot
```

## Quick start

```powershell
Import-Module Eigenverft.Manifested.Codex -Force

# Provision and activate the default slot
Initialize-CodexSlot -Name default

# Inspect the active setup
Get-CodexState
Test-CodexSlot -Name default
Get-CodexSlots

# Confirm Codex resolves from PATH
codex --version
```

## Slot model

Each slot gets its own npm prefix with an isolated `@openai/codex` install:

- Slot root: `$HOME\.codex-slots\<name>`
- Slot CLI prefix: `$HOME\.codex-slots\<name>\npm`
- Slot metadata: `$HOME\.codex-slots\<name>\slot.json`

The managed Node.js runtime is stored separately under `%LOCALAPPDATA%\CodexSlots\tools\node`. The active slot is tracked in `$HOME\.codex-slots\state.json`.

Switching slots with `Use-CodexSlot` updates `PATH` for both the current PowerShell process and the user environment.

## Common commands

### Provisioning and activation

```powershell
Initialize-CodexSlot -Name default
Initialize-CodexSlot -Name experimental -RefreshNode -ForceCodex
Use-CodexSlot -Name experimental
Test-CodexSlot -Name experimental
Get-CodexSlots
Get-CodexState
Remove-CodexSlot -Name experimental -Force
```

### Task execution

```powershell
# One-shot task in the current directory
Invoke-CodexTask -Prompt "summarize this repository"

# One-shot task in a specific directory
Invoke-CodexTask -Prompt "list the first file you see" -Directory "C:\work"

# Initial exec with Codex sandboxing instead of dangerous mode
Invoke-CodexTask -Prompt "inspect the repo" -Directory "C:\work" -AllowDangerous:$false -Sandbox workspace-write
```

### Named sessions

```powershell
# Start or continue a named wrapper session
Invoke-CodexTask -Prompt "read the repo and remember context" -Directory "C:\work\repo" -SessionName "repo1"

# Continue without respecifying the directory
Invoke-CodexTask -Prompt "apply the requested change" -SessionName "repo1"

# Inspect or maintain stored sessions
Get-CodexSession
Get-CodexSession -SessionName "repo1"
Set-CodexSessionDirectory -SessionName "repo1" -Directory "D:\other\repo"
Remove-CodexSession -SessionName "repo1" -Force
Clear-CodexSessions -Force
```

## Runtime and storage layout

Default locations:

- Slots root: `$HOME\.codex-slots`
- Local state root: `%LOCALAPPDATA%\CodexSlots`
- Node ZIP cache: `%LOCALAPPDATA%\CodexSlots\cache\node`
- Managed Node runtimes: `%LOCALAPPDATA%\CodexSlots\tools\node`
- Named session store: `%LOCALAPPDATA%\CodexSlots\sessions\named-sessions.json`

Useful inspection helpers:

- `Get-CodexManagerLayout`
- `Get-CodexSlotLayout -Name default`
- `Get-CodexManagerState`
- `Get-CodexSlotMetadata -Name default`
- `Resolve-CodexCommandPath`
- `Resolve-CodexDirectory -Directory C:\work`

## Command reference

Use `Get-Help <Command> -Full` for parameters and examples.

Slot management:

- `Get-CodexManagerLayout`
- `Get-CodexSlotLayout`
- `Initialize-CodexSlot`
- `Use-CodexSlot`
- `Test-CodexSlot`
- `Get-CodexSlots`
- `Remove-CodexSlot`
- `Get-CodexState`

Node runtime and cache:

- `Get-CodexNodeFlavor`
- `Get-CodexNodeReleaseOnline`
- `Get-CachedNodeZipFiles`
- `Get-LatestCachedNodeZip`
- `Get-CodexManagedNodeHome`
- `Test-CodexManagedNodeHome`
- `Get-CodexNodeExpectedSha256`
- `Ensure-CodexNodeZip`
- `Ensure-CodexNodeRuntime`

Metadata, install, and session helpers:

- `Get-CodexManagerState`
- `Get-CodexSlotMetadata`
- `Get-CodexPackageVersionFromSlot`
- `Install-CodexIntoSlot`
- `Resolve-CodexCommandPath`
- `Resolve-CodexDirectory`
- `Get-CodexSessionStorePath`
- `Get-CodexSession`
- `Remove-CodexSession`
- `Set-CodexSessionDirectory`
- `Clear-CodexSessions`
- `Invoke-CodexTask`

## Notes

- First-time initialization downloads the latest Node.js LTS ZIP for the current Windows architecture and verifies its SHA256 before extraction.
- If `nodejs.org` is unavailable later, the module can fall back to the newest cached ZIP already present on disk.
- `Invoke-CodexTask` defaults to `--dangerously-bypass-approvals-and-sandbox`. Use `-AllowDangerous:$false` if you want the initial run to use Codex sandboxing instead.
- Named sessions store the Codex thread id plus the last working directory. Resume runs temporarily change the PowerShell working directory because `codex exec resume` does not expose `--cd`.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Support

- Issues: https://github.com/eigenverft/Eigenverft.Manifested.Codex/issues
- Pull requests: https://github.com/eigenverft/Eigenverft.Manifested.Codex/pulls
