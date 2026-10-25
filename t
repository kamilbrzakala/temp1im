SELECT FileName, FileVersion, XDateInserted
FROM QBMFileRevision
WHERE FileName LIKE '%.dll'
  AND FileName NOT LIKE '%\%'                 -- tylko katalog główny
  AND XDateInserted < '2025-01-01'            -- sprzed instalacji 10.0
ORDER BY FileName;
