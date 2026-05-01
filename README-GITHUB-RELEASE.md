# SSH Key Manager

PowerShell WinForms tool for SSH key lifecycle operations:
- Generate key pairs
- Add keys to remote servers
- List and delete keys from `authorized_keys`
- Rotate keys across multiple servers

## Requirements

- Windows 10/11
- PowerShell 5.1+ (PowerShell 7 recommended)
- OpenSSH client installed (`ssh`, `ssh-keygen`)
- Access to target servers by SSH aliases from `~/.ssh/config`

## Build EXE

From this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build-exe.ps1
```

Output files:
- `ssh-manager.exe`
- `ssh-manager.exe.sha256.txt`

## Run (recommended)

Use `run.bat` as the primary launcher (double-click it):
- `run.bat` starts PowerShell with `-NoProfile` and runs `ssh-manager.ps1`.
- This is the most stable runtime mode for this project.

Alternative terminal launch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ssh-manager.ps1
```

## EXE note

`ssh-manager.exe` can be built, but for this project the script runtime is currently more reliable than ps2exe wrapper runtime.

## Notes

- App writes logs to `ssh-manager.log` in the same folder.
- SSH config is read-only; the tool does not edit SSH config files.
- Timeout can be configured in the app UI.

## Screenshots

Screenshots are strongly recommended for GitHub:
- Main window (Keys tab)
- Delete Keys tab
- Rotate Keys tab
- Status/log area during operation

Put images into `docs/screenshots/` and reference them in markdown:

```md
![Keys tab](docs/screenshots/keys-tab.png)
![Delete Keys tab](docs/screenshots/delete-keys-tab.png)
![Rotate Keys tab](docs/screenshots/rotate-keys-tab.png)
```

You can add screenshots manually from GitHub web UI too, but keeping them in repo is better for versioning.

## GitHub Release (quick)

1. Create repository (or use existing).
2. Upload source files (`*.ps1`, docs).
3. Create release tag (example: `v1.0.0`).
4. Attach binary assets:
   - `ssh-manager.exe`
   - `ssh-manager.exe.sha256.txt`
5. Publish release notes.

## Suggested Release Notes

### Highlights
- Stable WinForms SSH key manager
- Safe key deletion by exact key match
- Multi-server key rotation workflow
- Live status output during SSH operations

### Included artifacts
- `ssh-manager.exe`
- `ssh-manager.exe.sha256.txt`
