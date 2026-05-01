## SSH Key Manager v1.0.0

### What is included
- Windows executable build: `ssh-manager.exe`
- SHA256 checksum file: `ssh-manager.exe.sha256.txt`

### Main features
- Read SSH hosts from default/custom SSH config
- Generate SSH key pairs (with unique naming)
- Add selected key to remote `authorized_keys`
- Load and safely delete selected remote keys
- Rotate keys across multiple servers
- Live status output and configurable SSH timeout

### Notes
- SSH config is read-only in this tool.
- Log file is written to `ssh-manager.log` near executable.

### Verification
Use SHA256 file to verify downloaded binary before running.
