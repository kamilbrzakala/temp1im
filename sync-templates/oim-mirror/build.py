# Builds the per-recipe VB templates and one installer from CCC-OIMMirror.base.vb
import os
here=os.path.dirname(os.path.abspath(__file__))
base=open(os.path.join(here,'CCC-OIMMirror.base.vb')).read()
recipes=[
 dict(uid='CCC-0D1A2B3C4D5E4F60A1B2C3D4E5F60718', key='PERSON', name='Identities', file='CCC-OIMMirror-Identities.vb',
      tables=['Person'], late=[], filters={}),
 dict(uid='CCC-0D1A2B3C4D5E4F60A1B2C3D4E5F60719', key='ADS', name='Active Directory', file='CCC-OIMMirror-AD.vb',
      tables=['ADSForest','ADSDomain','ADSContainer','ADSGroup','ADSGroupInADSGroup','ADSAccount','ADSAccountInADSGroup',
              'ADSContact','ADSMachine','ADSContactInADSGroup','ADSMachineInADSGroup',
              'OrgHasADSGroup','DepartmentHasADSGroup','LocalityHasADSGroup','ProfitCenterHasADSGroup','AERoleHasADSGroup',
              'ITShopOrgHasADSGroup','ITShopSrcHasADSGroup','MirrorShopHasADSGroup',
              'ESetHasEntitlement'],
      late=['UID_AccProduct','UID_AERoleOwner','UID_Hardware','UID_HomeServer','UID_ProfileServer','UID_TerminalHomeServer','UID_TerminalProfileServer'],
      filters={'ESetHasEntitlement':"Entitlement LIKE '<Key><T>ADSGroup</T>%'"}),
]
def vbstr(x): return '"'+x.replace('"','""')+'"'
for r in recipes:
    code=base.replace('{{RECIPE_KEY}}',r['key']).replace('{{RECIPE_NAME}}',r['name'])
    code=code.replace('{{{TABLES}}}','{'+', '.join(vbstr(t) for t in r['tables'])+'}')
    code=code.replace('{{LATE_INIT}}', (' From {'+', '.join(vbstr(c) for c in r['late'])+'}') if r['late'] else '')
    code=code.replace('{{FILTER_INIT}}', (' From {'+', '.join('{'+vbstr(k)+', '+vbstr(v)+'}' for k,v in r['filters'].items())+'}') if r['filters'] else '')
    assert not any(p in code for p in ['{{RECIPE','{{{TABLES','{{LATE','{{FILTER'])
    r['code']=code
    open(os.path.join(here,r['file']),'w').write(code)
ps=['''<#
  Install-OIMMirrorTemplates.ps1
  Installs / updates the Synchronization Editor project templates ("recipes") for mirroring
  One Identity Manager v9.2 data into v10. Run it ONCE against the v10 database (never against v9.2).

  Recipes:'''] + ['    - OIM v9.2 to v10 mirror ({0})   [{1}]'.format(r['name'],r['uid']) for r in recipes] + ['''
  Then, in Synchronization Editor logged in to v10: New project -> Generic database connector ->
  SQL Server -> connection to the v9.2 database (untick "Fill in system description completely")
  -> pick the recipe -> read-only access. One project per recipe.

  Example:  .\\Install-OIMMirrorTemplates.ps1 -SqlServer sqlv10 -Database OneIM
            .\\Install-OIMMirrorTemplates.ps1 -SqlServer sqlv10 -Database OneIM -SqlUser sa -SqlPassword '...'
#>
param(
    [Parameter(Mandatory)] [string] $SqlServer,
    [Parameter(Mandatory)] [string] $Database,
    [string] $SqlUser,
    [string] $SqlPassword
)
$ErrorActionPreference = 'Stop'
$templates = @()
''']
for r in recipes:
    ps.append("$templates += [pscustomobject]@{ Uid = '%s'; Name = 'OIM v9.2 to v10 mirror (%s)'; Code = @'\n%s\n'@ }\n" % (r['uid'], r['name'], r['code']))
ps.append(r'''
if ($SqlUser) { $auth = "User ID=$SqlUser;Password=$SqlPassword" } else { $auth = 'Integrated Security=True' }
$cn = New-Object System.Data.SqlClient.SqlConnection "Server=$SqlServer;Database=$Database;$auth;TrustServerCertificate=True"
$cn.Open()
try {
    $chk = $cn.CreateCommand(); $chk.CommandText = "SELECT COUNT(*) FROM DialogDatabase WHERE IsMainDatabase = 1"; [void]$chk.ExecuteScalar()
    foreach ($t in $templates) {
        $c = $cn.CreateCommand()
        $c.CommandText = @"
IF EXISTS (SELECT 1 FROM DPRTemplate WHERE UID_DPRTemplate = @uid)
  UPDATE DPRTemplate SET ScriptCode = @code, DisplayName = @name, Revision = Revision + 1,
         XDateUpdated = GETUTCDATE(), XUserUpdated = SUSER_SNAME()
   WHERE UID_DPRTemplate = @uid
ELSE
  INSERT INTO DPRTemplate (UID_DPRTemplate, DisplayName, Description, ScriptCode, ScriptLanguage, SupportedScriptLanguages,
         ConnectedSystem, ConnectedSystemSubType, ConnectedSystemVersion, TemplateType, IsGenerated, Revision, SortOrder,
         XObjectKey, XDateInserted, XDateUpdated, XUserInserted, XUserUpdated)
  VALUES (@uid, @name,
         'Mirror of One Identity Manager v9.2 data into v10 via the generic MSSQL connector (read-only, matching by UID).',
         @code, 'VisualBasicNet', 'VisualBasicNet', 'DB', 'MSSql', '7.0.2015.402', 'ShellTemplate', 0, 1, 0,
         '<Key><T>DPRTemplate</T><P>' + @uid + '</P></Key>', GETUTCDATE(), GETUTCDATE(), SUSER_SNAME(), SUSER_SNAME())
"@
        [void]$c.Parameters.AddWithValue('@uid', $t.Uid)
        [void]$c.Parameters.AddWithValue('@name', $t.Name)
        [void]$c.Parameters.AddWithValue('@code', $t.Code)
        [void]$c.ExecuteNonQuery()
        Write-Host "Installed: $($t.Name)"
    }
}
finally { $cn.Close() }
''')
open(os.path.join(here,'Install-OIMMirrorTemplates.ps1'),'w',encoding='utf-8-sig').write(''.join(ps))
print('ok')
