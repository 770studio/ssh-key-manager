# Release Checklist

## Pre-release verification

- [ ] `ssh-manager.ps1` starts without syntax errors
- [ ] Default SSH config loading works
- [ ] Custom SSH config loading works
- [ ] Key generation works and creates `.pub`
- [ ] Add key works for at least one remote host
- [ ] Load keys from remote host works
- [ ] Delete selected keys works safely
- [ ] Rotate keys tab works across multiple hosts
- [ ] Timeout field in UI works and validates input
- [ ] `ssh-manager.log` records operation details

## Build

- [ ] Run `.\build-exe.ps1`
- [ ] Confirm `ssh-manager.exe` exists
- [ ] Confirm `ssh-manager.exe.sha256.txt` exists
- [ ] Verify hash file matches exe

## GitHub publication

- [ ] Push source files to repository
- [ ] Create tag (example: `v1.0.0`)
- [ ] Create GitHub Release from tag
- [ ] Attach:
  - [ ] `ssh-manager.exe`
  - [ ] `ssh-manager.exe.sha256.txt`
- [ ] Add release notes
- [ ] Publish release

## Post-release

- [ ] Download release from GitHub on clean machine
- [ ] Validate SHA256
- [ ] Run app and verify main flows
