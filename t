# 1) Którą wersję usługi faktycznie uruchamiamy
$svc = Get-CimInstance Win32_Service | ? { $_.PathName -match 'One Identity' -or $_.Name -like 'viJobService*' }
$svc | select Name, State, StartName, PathName | fl
$dir = Split-Path (($svc.PathName -replace '"','') -split '\.exe')[0]
"VI.DB.dll       : " + (Get-Item "$dir\VI.DB.dll").VersionInfo.FileVersion
"JobService.dll  : " + (Get-Item "$dir\JobService.dll" -ErrorAction SilentlyContinue).VersionInfo.FileVersion
"Katalog         : $dir"

# 2) Z czym się łączy pod nazwą/IP z JobService.cfg (wstaw to, co wpisałeś w Job Service Configuration)
$srv = 'FHCDBIDMMP02'
Resolve-DnsName $srv -ErrorAction SilentlyContinue | select Name, IPAddress
$cn = New-Object System.Data.SqlClient.SqlConnection "Server=$srv;Database=D1IM;Integrated Security=True"
$cn.Open(); $c = $cn.CreateCommand()
$c.CommandText = "select @@SERVERNAME, cast(SERVERPROPERTY('ProductVersion') as varchar(30)), cast(CONNECTIONPROPERTY('local_net_address') as varchar(30))"
$r = $c.ExecuteReader(); $null = $r.Read(); "SQL: {0} | {1} | {2}" -f $r[0],$r[1],$r[2]; $cn.Close()

# 3) Co mówi log przy ostatniej próbie
Select-String C:\OIMLogs\JobService.log -Pattern '810264','data source','Connect','Version' | select -Last 30
