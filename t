SELECT sh.DisplayName, sc.Name, sc.ConnectionParameter
FROM DPRSystemConnection sc JOIN DPRShell sh ON sh.UID_DPRShell = sc.UID_DPRShell
WHERE sc.ConnectionParameter LIKE '%data source=%';

BEGIN TRAN;
UPDATE DPRSystemConnection
SET ConnectionParameter = REPLACE(ConnectionParameter, 'data source=FHCDBIDMMP01;', 'data source=10.212.5.36;'),
    XDateUpdated = GETUTCDATE()
WHERE ConnectionParameter LIKE '%data source=FHCDBIDMMP01;%'
  AND ConnectionParameter LIKE '%initial catalog=D1IM;%';   -- tylko połączenia do bazy OIM
-- sprawdź, potem COMMIT


### HOSTS


$entries = @'

# --- OIM clone env: wszystkie odwołania do D1IM -> nowy SQL 2022 (MP02) ---
10.212.5.36   FHCDBIDMMP01 FHCDBIDMMP01.fhlbc.loc
10.212.5.36   FHCDBIDMMP02 FHCDBIDMMP02.fhlbc.loc
'@
Add-Content -Path "$env:windir\System32\drivers\etc\hosts" -Value $entries -Encoding ASCII
ipconfig /flushdns
Resolve-DnsName FHCDBIDMMP01 | select Name, IPAddress   # ma być .36
Resolve-DnsName FHCDBIDMMP02 | select Name, IPAddress   # ma być .36
Restart-Service OneIMService
