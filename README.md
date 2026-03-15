# Eigenverft.Manifested.Codex

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Codex?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Codex) [![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/Eigenverft.Manifested.Codex?label=Downloads&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Codex) [![PowerShell Support](https://img.shields.io/badge/PowerShell-5.1%2B%20Desktop%2FCore-5391FE?logo=powershell&logoColor=white)](source/Eigenverft.Manifested.Codex/Eigenverft.Manifested.Codex.psd1) [![Build Status](https://img.shields.io/github/actions/workflow/status/eigenverft/Eigenverft.Manifested.Codex/cicd.yml?branch=main&label=build)](https://github.com/eigenverft/Eigenverft.Manifested.Codex/actions/workflows/cicd.yml) [![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Codex?logo=mit)](LICENSE)

Windows-focused PowerShell module that provides a thin wrapper around the OpenAI Codex CLI for task execution, named sessions, and lightweight local state inspection.

## 🎯 Motivation

Eigenverft.Manifested.Codex exists to put the Codex CLI inside a controllable PowerShell wrapper, so agent runs can be steered from scripts, jobs, and repeatable tooling instead of only by hand. The goal is simple: make sandboxed, programmable agentic work practical, with enough structure to automate tasks, preserve context, and reliably continue where a run left off.

🚀 **Key Features:**
- Wraps `codex exec` and `codex exec resume` for repeatable PowerShell-driven runs
- Persists named wrapper sessions in `%LOCALAPPDATA%\CodexSlots\sessions\named-sessions.json`
- Tracks the last working directory per named session
- Captures the last agent message from JSON output for lightweight inspection
- Exposes simple session and state helpers for listing, updating, and clearing wrapper metadata

---

## ✅ Requirements

- Windows
- PowerShell 5.1 or newer
- A working `codex` or `codex.cmd` on `PATH`
- Any Codex CLI authentication or account setup required by your environment

---

## 📥 Installation

### 🔧 Bootstrapper (Windows)

Use the supported bootstrap entrypoint:

```powershell
iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Codex/refs/heads/main/iwr/bootstrapper.ps1 | iex
```

The bootstrapper installs `PowerShellGet`, `PackageManagement`, and `Eigenverft.Manifested.Codex` from PSGallery, opens a new Windows PowerShell console, imports the module, and runs `Get-CodexVersion`.

### 📦 Direct Install

```powershell
Install-Module -Name Eigenverft.Manifested.Codex -Repository PSGallery -Scope CurrentUser -Force
Import-Module Eigenverft.Manifested.Codex -Force
Get-CodexVersion
```

### 🧱 Sandbox Companion

If you want to use this project inside a disposable Windows Sandbox session, [`Eigenverft.Manifested.Sandbox`](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox) is the fastest companion setup. It can bootstrap a fresh sandbox into a Codex-ready environment, provision the CLI and supporting runtimes, and give `Eigenverft.Manifested.Codex` a clean place to run programmable agent workflows safely and repeatably.

---

## 🏁 Quick Start

```powershell
Import-Module Eigenverft.Manifested.Codex -Force

Get-CodexVersion
Get-CodexState

# One-shot task in the current directory
Invoke-CodexTask -Prompt "summarize this repository"

# One-shot task in a specific directory
Invoke-CodexTask -Prompt "list the first file you see" -Directory "C:\work"
```

### 🔁 Named Sessions

```powershell
# Start or continue a named wrapper session
Invoke-CodexTask -Prompt "read the repo and remember context" -Directory "C:\work\repo" -SessionName "repo1"

# Continue without respecifying the directory
Invoke-CodexTask -Prompt "apply the requested change" -SessionName "repo1"
```

---

## 📚 Command Reference

> 💡 Use `Get-Help <FunctionName>` for parameters, examples, and command details.

### ▶️ Execution

- `Get-CodexVersion` Resolve the available `codex` command and return version information.
- `Invoke-CodexTask` Run a one-shot Codex task or resume a named wrapper session.

### 🧭 State & Path Helpers

- `Get-CodexState` Return wrapper readiness, local paths, and session-store status.
- `Resolve-CodexCommandPath` Resolve `codex` or `codex.cmd` from `PATH`.
- `Resolve-CodexDirectory` Normalize and validate the working directory for a task run.
- `Get-CodexSessionStorePath` Return the JSON file used for named wrapper sessions.

### 🗂️ Session Helpers

- `Get-CodexSession` List all stored named sessions or fetch a specific one.
- `Set-CodexSessionDirectory` Update the stored last directory for an existing session.
- `Remove-CodexSession` Remove a single stored wrapper session.
- `Clear-CodexSessions` Clear all stored wrapper-managed sessions.

---

## 🧾 State Surface

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

---

## 📝 Behavior Notes

- `Invoke-CodexTask` preserves the wrapper contract for both one-shot and named-session flows.
- Named sessions store only wrapper-side metadata: session name, thread id, last directory, and update timestamp.
- Advanced session maintenance helpers remain available if you need to inspect or clear wrapper-managed session metadata.
- The wrapper defaults to `--dangerously-bypass-approvals-and-sandbox`. Use `-AllowDangerous:$false` if you want the initial run to use Codex sandboxing instead.
- Resume runs temporarily change the PowerShell working directory because `codex exec resume` does not expose `--cd`.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## 📫 Contact & Support

For questions and support:

- 🐛 Open an [issue](https://github.com/eigenverft/Eigenverft.Manifested.Codex/issues) in this repository
- 🤝 Submit a [pull request](https://github.com/eigenverft/Eigenverft.Manifested.Codex/pulls) with improvements

---

<div align="center">
Made with ❤️ by Eigenverft
</div>
