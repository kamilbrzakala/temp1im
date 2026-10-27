-- which queues are getting jobs
SELECT Queue, Ready2EXE, COUNT(*) AS cnt
FROM JobQueue GROUP BY Queue, Ready2EXE ORDER BY Queue;

-- which job servers exist and what they're tagged with
SELECT s.Ident_Server, s.Queue, t.Ident_QBMServerTag
FROM QBMServer s
LEFT JOIN QBMServerHasServerTag x ON x.UID_QBMServer = s.UID_QBMServer
LEFT JOIN QBMServerTag t ON t.UID_QBMServerTag = x.UID_QBMServerTag
ORDER BY s.Ident_Server;

-- which server each sync project uses
SELECT sh.DisplayName, s.Ident_Server, s.Queue
FROM DPRRootObjConnectionInfo ci
JOIN DPRSystemVariableSet vs ON vs.UID_DPRSystemVariableSet = ci.UID_DPRSystemVariableSet
JOIN DPRShell sh ON sh.UID_DPRShell = vs.UID_DPRShell
LEFT JOIN QBMServer s ON s.UID_QBMServer = ci.UID_QBMServer;
