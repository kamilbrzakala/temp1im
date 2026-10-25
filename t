1. Pliki wgrane ręcznie (Software Loader):

sql
SELECT FileName, FileVersion, XUserInserted, XDateInserted, XUserUpdated, XDateUpdated
FROM QBMFileRevision
WHERE XUserInserted NOT LIKE 'QBM[_]%'
ORDER BY XDateInserted;

2. Konkretnie te, które przy upgradzie wywalały kompilację:

sql
SELECT FileName, FileVersion, XUserInserted, XDateInserted
FROM QBMFileRevision
WHERE FileName LIKE '%IdentityModel.Clients%'
   OR FileName LIKE '%Oracle.ManagedDataAccess%'
   OR FileName LIKE '%Stimulsoft.Report%'
   OR FileName LIKE '%DataSetExtensions%'
   OR FileName LIKE '%DirectoryServices.AccountManagement%';

3. Skrypty, które wymuszają referencje. Kompilator szuka pakietu NuGet dla każdego #R (a #A dotyczy DLL-ek), więc warto sprawdzić, które skrypty ich używają:

sql
SELECT ScriptName, XUserUpdated, XDateUpdated,
       SUBSTRING(ScriptCode, CHARINDEX('#R', ScriptCode), 120) AS FirstRef
FROM DialogScript
WHERE ScriptCode LIKE '%#R %' OR ScriptCode LIKE '%#A %';
