Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "\ssh-manager.ps1"""

Set shell = CreateObject("WScript.Shell")
shell.Run cmd, 0, False
