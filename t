# 1. Dokładnie to, co sprawdza Web Installer
$p = [Environment]::ExpandEnvironmentVariables('%programfiles%\IIS\Asp.Net Core Module\V2')
"Ścieżka: $p  ->  istnieje: $(Test-Path $p)"
"Proces 64-bit: $([Environment]::Is64BitProcess)"

# 2. Runtime'y .NET (OIM 10 potrzebuje 10.x: NETCore + AspNetCore + WindowsDesktop)
dotnet --list-runtimes

# 3. Zainstalowane Hosting Bundle
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  ? DisplayName -match 'Hosting|Core Module' | select DisplayName, DisplayVersion

# 4. Czy moduł jest zarejestrowany w IIS
& "$env:windir\System32\inetsrv\appcmd.exe" list modules | Select-String AspNetCore
Select-String "$env:windir\System32\inetsrv\config\applicationHost.config" -Pattern 'AspNetCoreModuleV2'

# 5. Role IIS
Get-WindowsFeature Web-Server, Web-Windows-Auth, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-WebSockets, Web-Mgmt-Console |
  ft Name, InstallState
