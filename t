# A. Sprawdź stan IIS
Get-ChildItem C:\Windows\System32\inetsrv\config
Get-ChildItem C:\inetpub\history -EA SilentlyContinue   # automatyczne kopie konfiguracji
Get-Service W3SVC, WAS

  Uninstall-WindowsFeature Web-Server -IncludeManagementTools   # potem restart
  Install-WindowsFeature Web-Server, Web-Windows-Auth, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-WebSockets -IncludeManagementTools

# B. Gdy applicationHost.config już istnieje, napraw Hosting Bundle z logiem
.\dotnet-hosting-10.0.14-win.exe /repair /log C:\temp\hb.log
iisreset

# C. Weryfikacja: oba polecenia muszą coś zwrócić
Test-Path 'C:\Program Files\IIS\Asp.Net Core Module\V2'
& "$env:windir\System32\inetsrv\appcmd.exe" list modules | Select-String AspNetCore
