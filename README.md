# Eigenverft.Manifested.Codex

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Codex?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Codex)
[![PowerShell Gallery Platform Support](https://img.shields.io/powershellgallery/p/Eigenverft.Manifested.Codex?logo=windows)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Codex)
[![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Codex?logo=mit)](LICENSE)

Windows-focused PowerShell module that provides a thin wrapper around the OpenAI Codex CLI for task execution, named sessions, and lightweight local state inspection.

## What It Does

- Resolves `codex` from `PATH`
- Wraps `codex exec` and `codex exec resume`
- Persists named wrapper sessions in `%LOCALAPPDATA%\CodexSlots\sessions\named-sessions.json`
- Tracks the last working directory per named session
- Extracts and stores the last agent message from JSON output
- Exposes a small inspection surface for the wrapper state

## Requirements

- Windows
- PowerShell 5.1 or newer
- A working `codex` or `codex.cmd` on `PATH`
- Any Codex CLI authentication or account setup required by your environment

## Bootstrapper

The supported bootstrap entrypoint is:

```powershell
iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Codex/refs/heads/main/iwr/bootstrapper.ps1 | iex
```

The bootstrapper installs `PowerShellGet`, `PackageManagement`, and `Eigenverft.Manifested.Codex` from PSGallery, opens a new Windows PowerShell console, imports the module, and runs `Get-CodexVersion`.

## Direct Install

```powershell
Install-Module -Name Eigenverft.Manifested.Codex -Repository PSGallery -Scope CurrentUser -Force
Import-Module Eigenverft.Manifested.Codex -Force
Get-CodexVersion
```

## Quick Start

```powershell
Import-Module Eigenverft.Manifested.Codex -Force

Get-CodexVersion
Get-CodexState

# One-shot task in the current directory
Invoke-CodexTask -Prompt "summarize this repository"

# One-shot task in a specific directory
Invoke-CodexTask -Prompt "list the first file you see" -Directory "C:\work"
```

## Named Sessions

```powershell
# Start or continue a named wrapper session
Invoke-CodexTask -Prompt "read the repo and remember context" -Directory "C:\work\repo" -SessionName "repo1"

# Continue without respecifying the directory
Invoke-CodexTask -Prompt "apply the requested change" -SessionName "repo1"
```

## State Surface

`Get-CodexState` returns lightweight wrapper state:

- `LocalRoot`
- `SessionStorePath`
- `SessionStoreExists`
- `SessionCount`
- `CodexCommandPath`
- `CodexAvailable`
- `ReadyToRun`

Default local state path:

- `%LOCALAPPDATA%\CodexSlots`
- `%LOCALAPPDATA%\CodexSlots\sessions\named-sessions.json`

## Notes

- `Invoke-CodexTask` preserves the existing wrapper contract for one-shot and named-session flows.
- Named sessions store only wrapper-side metadata: session name, thread id, last directory, and update timestamp.
- Advanced session maintenance helpers remain available if you need to inspect or clear wrapper-managed session metadata. Use `Get-Help` for details.
- The wrapper defaults to `--dangerously-bypass-approvals-and-sandbox`. Use `-AllowDangerous:$false` if you want the initial run to use Codex sandboxing instead.
- Resume runs temporarily change the PowerShell working directory because `codex exec resume` does not expose `--cd`.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
