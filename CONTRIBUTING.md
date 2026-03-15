# Contributing

Thanks for helping improve `Eigenverft.Manifested.Codex`.

This repository packages a Windows-focused PowerShell wrapper around the OpenAI Codex CLI, with a strong emphasis on repeatable task execution, named sessions, and lightweight local state inspection. Contributions should preserve that focus and keep the module straightforward to script and operate.

## Before You Start

- Open an issue for bugs, workflow gaps, or proposals before starting larger changes.
- Keep changes scoped to the module's wrapper behavior, install path, session handling, or supporting documentation.
- Review [README.md](README.md) and [SECURITY.md](SECURITY.md) before opening a pull request.

## Development Notes

- Target Windows and PowerShell 5.1+ compatibility unless the change is explicitly documented as narrowing support.
- Keep the public command surface and session storage behavior intentional and easy to reason about.
- If you update packaging or release automation, review the workflow files under `.github/workflows/`.

## Local Validation

Use the smallest validation set that matches the scope of your change.

```powershell
Test-ModuleManifest .\source\Eigenverft.Manifested.Codex\Eigenverft.Manifested.Codex.psd1
. .\source\Eigenverft.Manifested.Codex.TestImports.ps1
Import-Module .\source\Eigenverft.Manifested.Codex\Eigenverft.Manifested.Codex.psd1 -Force
Get-CodexState
```

If your change affects command execution paths, also validate the relevant `Get-Help` output and any example flows you touched in the README.

## Pull Requests

- Describe the user-facing problem and the behavior change clearly.
- Call out any Windows, PowerShell version, or Codex CLI assumptions.
- Update README or help-facing content when install, usage, or operational behavior changes.
- Keep pull requests focused so validation and review stay easy to follow.

## Security

Do not open public issues for suspected vulnerabilities. Use the private reporting guidance in [SECURITY.md](SECURITY.md) instead.
