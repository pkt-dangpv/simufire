# Project-wide instructions

- Every script or program created or modified for SimuFire must work from both the desktop checkout on `F:` and the laptop checkout on `C:`.
- Do not hard-code a machine-specific drive, username, or absolute project path. Resolve project-relative paths from the script/file location (for example, Python `__file__`, PowerShell `$PSScriptRoot`, or Godot's project root), not from the current working directory.
- Resolve external tools and machine-local resources through explicit arguments, environment variables, `PATH`, or documented per-machine settings. If a dependency cannot be found, report a clear actionable error rather than assuming `C:` or `F:`.
- Preserve compatibility with Windows paths containing spaces, Unicode characters, and OneDrive folder names. Validate behavior from both checkout locations when practical.
