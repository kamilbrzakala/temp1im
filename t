sql
BEGIN TRAN;
UPDATE DPRSystemConnection
SET ConnectionParameter = REPLACE(ConnectionParameter, 'data source=FHCDBIDMMP02;', 'data source=10.212.5.36;'),
    XDateUpdated = GETUTCDATE()
WHERE ConnectionParameter LIKE '%data source=FHCDBIDMMP02;%';

SELECT sh.DisplayName, sc.ConnectionParameter
FROM DPRSystemConnection sc JOIN DPRShell sh ON sh.UID_DPRShell = sc.UID_DPRShell
WHERE sc.ConnectionParameter LIKE '%data source=%';
-- COMMIT;

Sprawdź przy okazji, czy któryś projekt nie ma też FHCDBIDMMP01 i popraw go analogicznie.

Jeśli UPDATE też wisi, to coś blokuje wiersz. Najpewniej Job Service ciągle próbuje migracji. Sprawdź to tak:

sql
SELECT session_id, blocking_session_id, wait_type, command, host_name = (SELECT host_name FROM sys.dm_exec_sessions s WHERE s.session_id = r.blocking_session_id)
FROM sys.dm_exec_requests r
WHERE blocking_session_id <> 0;
