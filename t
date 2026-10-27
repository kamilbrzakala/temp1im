foreach ($s in '10.212.5.36','10.212.5.35','10.212.5.55','FHCDBIDMMP01','FHCDBIDMMP02') {
  try {
    $cn = New-Object System.Data.SqlClient.SqlConnection "Server=$s;Database=master;Integrated Security=True;Connect Timeout=5"
    $cn.Open(); $c = $cn.CreateCommand()
    $c.CommandText = "select @@SERVERNAME, cast(SERVERPROPERTY('ProductVersion') as varchar(30)), (select count(*) from sys.databases where name='D1IM')"
    $r = $c.ExecuteReader(); $null = $r.Read()
    "{0,-14} -> {1} | {2} | D1IM:{3}" -f $s, $r[0], $r[1], $r[2]; $cn.Close()
  } catch { "{0,-14} -> ERROR: {1}" -f $s, $_.Exception.GetBaseException().Message }
}

# końcówka logu zamiast całego pliku
Get-Content C:\OIMLogs\JobService.log -Tail 400 | Select-String '810264','data source','Connecting','Server=' | select -Last 20
