# Eigenverft.Manifested.Agent

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Agent?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Agent) [![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/Eigenverft.Manifested.Agent?label=Downloads&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Agent) [![PowerShell Support](https://img.shields.io/badge/PowerShell-5.1%2B%20Desktop%2FCore-5391FE?logo=powershell&logoColor=white)](source/Eigenverft.Manifested.Agent/Eigenverft.Manifested.Agent.psd1) [![Build Status](https://img.shields.io/github/actions/workflow/status/eigenverft/Eigenverft.Manifested.Agent/cicd.yml?branch=main&label=build)](https://github.com/eigenverft/Eigenverft.Manifested.Agent/actions/workflows/cicd.yml) [![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Agent?logo=mit)](LICENSE)

Windows-focused PowerShell module that provides thin wrappers around agent CLIs, including the OpenAI Codex CLI and experimental Gemini CLI task execution, named sessions, and lightweight local state inspection.

## 🎯 Motivation

Eigenverft.Manifested.Agent exists to put agent CLIs like Codex and Gemini inside a controllable PowerShell wrapper, so agent runs can be steered from scripts, jobs, and repeatable tooling instead of only by hand. The goal is simple: make sandboxed, programmable agentic work practical, with enough structure to automate tasks, preserve context, and reliably continue where a run left off.

🚀 **Key Features:**
- Wraps `codex exec` and `codex exec resume` for repeatable PowerShell-driven runs
- Adds experimental `Invoke-GeminiTask` support for Gemini CLI headless runs
- Persists named wrapper sessions in `%LOCALAPPDATA%\Eigenverft.Manifested.Agent\sessions\named-sessions.json`
- Tracks the last working directory per named session
- Captures the last agent message from JSON output for lightweight inspection
- Exposes simple session and state helpers for listing, updating, and clearing wrapper metadata

---

## ✅ Requirements

- Windows
- PowerShell 5.1 or newer
- A working `codex` or `codex.cmd` on `PATH` if you use the Codex commands
- A working `gemini`, `gemini.cmd`, or `gemini.ps1` on `PATH` if you use `Invoke-GeminiTask`
- Any Codex CLI or Gemini CLI authentication/account setup required by your environment

---

## 📥 Installation

### 🔧 Bootstrapper (Windows)

Use the supported bootstrap entrypoint:

```powershell
iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Agent/refs/heads/main/iwr/bootstrapper.ps1 | iex
```

The bootstrapper installs `PowerShellGet`, `PackageManagement`, and `Eigenverft.Manifested.Agent` from PSGallery, opens a new Windows PowerShell console, imports the module, and runs `Get-CodexVersion`.

### 📦 Direct Install

```powershell
Install-Module -Name Eigenverft.Manifested.Agent -Repository PSGallery -Scope CurrentUser -Force
Import-Module Eigenverft.Manifested.Agent -Force
Get-CodexVersion
```

### 🧱 Sandbox Companion

If you want to use this project inside a disposable Windows Sandbox session, [`Eigenverft.Manifested.Sandbox`](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox) is the fastest companion setup. It can bootstrap a fresh sandbox into an agent-ready environment, provision the CLI and supporting runtimes, and give `Eigenverft.Manifested.Agent` a clean place to run programmable agent workflows safely and repeatably.

---

## 🏁 Quick Start

```powershell
Import-Module Eigenverft.Manifested.Agent -Force

Get-CodexVersion
Get-CodexState

# One-shot task in the current directory
Invoke-CodexTask -Prompt "summarize this repository"

# One-shot task in a specific directory
Invoke-CodexTask -Prompt "list the first file you see" -Directory "C:\work"

# Experimental Gemini one-shot task in the current directory
Invoke-GeminiTask -Prompt "summarize this repository"
```

### 🔁 Named Sessions

```powershell
# Start or continue a named wrapper session
Invoke-CodexTask -Prompt "read the repo and remember context" -Directory "C:\work\repo" -SessionName "repo1"

# Continue without respecifying the directory
Invoke-CodexTask -Prompt "apply the requested change" -SessionName "repo1"
```

### ♊ Experimental Gemini Sessions

```powershell
# Start or continue a named Gemini wrapper session
Invoke-GeminiTask -Prompt "read the repo and remember context" -Directory "C:\work\repo" -SessionName "gemini-repo1"

# Continue without respecifying the directory
Invoke-GeminiTask -Prompt "apply the requested change" -SessionName "gemini-repo1"
```

---

## 📚 Command Reference

> 💡 Use `Get-Help <FunctionName>` for parameters, examples, and command details.

### ▶️ Execution

- `Get-CodexVersion` Resolve the available `codex` command and return version information.
- `Invoke-CodexTask` Run a one-shot Codex task or resume a named wrapper session.
- `Invoke-GeminiTask` Run an experimental Gemini headless task or resume a named wrapper session backed by Gemini session ids.

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

- `%LOCALAPPDATA%\Eigenverft.Manifested.Agent`
- `%LOCALAPPDATA%\Eigenverft.Manifested.Agent\sessions\named-sessions.json`

---

## 📝 Behavior Notes

- `Invoke-CodexTask` preserves the wrapper contract for both one-shot and named-session flows.
- Named sessions store only wrapper-side metadata: session name, thread id, last directory, and update timestamp.
- Advanced session maintenance helpers remain available if you need to inspect or clear wrapper-managed session metadata.
- The wrapper defaults to `--dangerously-bypass-approvals-and-sandbox`. Use `-AllowDangerous:$false` if you want the initial run to use Codex sandboxing instead.
- Resume runs temporarily change the PowerShell working directory because `codex exec resume` does not expose `--cd`.
- `Invoke-GeminiTask` is experimental and intentionally keeps a smaller public surface than the Codex wrapper.
- Gemini named sessions are stored separately at `%LOCALAPPDATA%\Eigenverft.Manifested.Agent\sessions\named-gemini-sessions.json`.
- Gemini session continuity is project-scoped. The wrapper keeps a friendly session name that maps to the last observed Gemini session id for that directory.
- Before resuming a named Gemini session, the wrapper runs `gemini --list-sessions` in the effective directory and starts a fresh session if the stored Gemini id is no longer listed.
- `Invoke-GeminiTask` uses `--approval-mode yolo` when `-AllowDangerous:$true` and `--sandbox` when `-AllowDangerous:$false`.
- Gemini trust, auth, and session availability remain controlled by the Gemini CLI itself, so wrapper resumes are best-effort if the native session state changes outside PowerShell.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## 📫 Contact & Support

For questions and support:

- 🐛 Open an [issue](https://github.com/eigenverft/Eigenverft.Manifested.Agent/issues) in this repository
- 🤝 Submit a [pull request](https://github.com/eigenverft/Eigenverft.Manifested.Agent/pulls) with improvements

---

<div align="center">
Made with ❤️ by Eigenverft
</div>
