' Codex++ DeepSeek ???? - ??????
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
helper = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "deepseek-usage-helper.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & helper & """"
shell.Run cmd, 0, False
