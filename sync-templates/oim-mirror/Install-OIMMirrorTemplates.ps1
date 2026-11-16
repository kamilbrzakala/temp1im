<#
  Install-OIMMirrorTemplates.ps1
  Installs / updates the Synchronization Editor project templates ("recipes") for mirroring
  One Identity Manager v9.2 data into v10. Run it ONCE against the v10 database (never against v9.2).

  Recipes:    - OIM v9.2 to v10 mirror (Identities)   [CCC-0D1A2B3C4D5E4F60A1B2C3D4E5F60718]    - OIM v9.2 to v10 mirror (Active Directory)   [CCC-0D1A2B3C4D5E4F60A1B2C3D4E5F60719]
  Then, in Synchronization Editor logged in to v10: New project -> Generic database connector ->
  SQL Server -> connection to the v9.2 database (untick "Fill in system description completely")
  -> pick the recipe -> read-only access. One project per recipe.

  Example:  .\Install-OIMMirrorTemplates.ps1 -SqlServer sqlv10 -Database OneIM
            .\Install-OIMMirrorTemplates.ps1 -SqlServer sqlv10 -Database OneIM -SqlUser sa -SqlPassword '...'
#>
param(
    [Parameter(Mandatory)] [string] $SqlServer,
    [Parameter(Mandatory)] [string] $Database,
    [string] $SqlUser,
    [string] $SqlPassword
)
$ErrorActionPreference = 'Stop'
$templates = @()
$templates += [pscustomobject]@{ Uid = 'CCC-0D1A2B3C4D5E4F60A1B2C3D4E5F60718'; Name = 'OIM v9.2 to v10 mirror (Identities)'; Code = @'
References VI.Parsers.dll
References VI.TSUtils.dll
References VI.DB.dll
References VI.Projector.Database.dll
References VI.Projector.Database.Native.dll
References System.Xml.dll
References System.Xml.Linq.dll
References System.Core.dll

Imports VI.Projector
Imports VI.Projector.Projection
Imports VI.Projector.Database
Imports VI.Projector.Connection.Scope
Imports VI.Projector.Filter
Imports VI.Projector.Schema
Imports VI.Projector.Mapping.Rules
Imports VI.Projector.Mapping
Imports VI.Base
Imports VI.DB.Compatibility
Imports VI.DB
Imports VI.Projector.Connection
Imports VI.Projector.Scripting
Imports VI.Projector.Variables
Imports VI.DB.Entities
Imports VI.Parsers.Conditions
Imports VI.Projector.Templates

Imports System
Imports System.Collections.Generic
Imports System.Linq
Imports System.Text

	' ============================================================================
	' OIM v9.2 -> v10 mirror template
	' Left  = MainConnection (this One Identity Manager v10 database)
	' Right = ConnectedSystemConnection (generic MSSQL connector on the v9.2 database, read-only)
	' Matching by primary key (UID / UID pair), direction: to One Identity Manager only.
	' ============================================================================

	' ---- configuration: tables in workflow order ----
	Private Const m_RecipeKey As String = "PERSON"
	Private Const m_RecipeName As String = "Identities"
	Private ReadOnly m_Tables As String() = {"Person"}

	' ---- reference columns filled in a second step (<Table>_Refs), so the objects they point to
	'      can be migrated later (IT Shop products, owners, servers, hardware) ----
	Private ReadOnly m_LateColumns As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) 

	' ---- source (v9.2) scope filters: table -> SQL condition ----
	Private ReadOnly m_SourceFilters As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) 

	' ---- columns never mapped ----
	Private ReadOnly m_ExcludedColumns As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
		"XObjectKey", "XDateInserted", "XDateUpdated", "XUserInserted", "XUserUpdated",
		"XTouched", "XDateSubItem", "XMarkedForDeletion", "XOrigin", "XIsInEffect", "RiskIndexCalculated"}

	Private Const m_TargetSystemType As String = "OIMMIRROR"
	Private Const m_TargetSystemTypeDisplay As String = "OIM v9.2 mirror"
	Private ReadOnly m_WorkflowNameMirror As String = "Mirror v9.2 to v10 (" & m_RecipeName & ")"
	Private ReadOnly m_LogFile As String = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "OIMMirror-template-log.txt")

	Private m_user_id As String
	Private m_dataSource As String
	Private m_initialCatalog As String
	Private m_password As String
	Private m_pooling As String
	Private m_rootIdentifier As String

	' table -> PK columns, crypted columns, self reference columns (from DialogColumn / QBMRelation of v10)
	Private m_PkColumns As New Dictionary(Of String, List(Of String))(StringComparer.OrdinalIgnoreCase)
	Private m_CryptedColumns As New Dictionary(Of String, HashSet(Of String))(StringComparer.OrdinalIgnoreCase)
	Private m_SelfRefColumns As New Dictionary(Of String, HashSet(Of String))(StringComparer.OrdinalIgnoreCase)
	Private m_MapOrder As New List(Of String)

	Public Property DbSession As ISession
		Get
			Return m_DbSession
		End Get
		Private Set(value As ISession)
			m_DbSession = value
		End Set
	End Property
	Private m_DbSession As ISession

	Public Overrides ReadOnly Property Capabilities As ShellScriptCapabilities
		Get
			Return ShellScriptCapabilities.Default
		End Get
	End Property

	Private Sub Log(msg As String)
		Try
			System.IO.File.AppendAllText(m_LogFile, DateTime.Now.ToString("s") & " " & msg & Environment.NewLine)
		Catch
		End Try
	End Sub

	Protected Overrides Sub OnPreProcessing()
		Log("=== OnPreProcessing")
		Dim con As ISystemConnection = GetConnection("ConnectedSystemConnection")
		m_dataSource = con.ConnectionParameter("data source", "").ToString()
		m_initialCatalog = con.ConnectionParameter("initial catalog", "").ToString()
		m_user_id = SystemVariable.Unmask(con.ConnectionParameter("user id", "").ToString())
		m_password = SystemVariable.Unmask(con.ConnectionParameter("password", "").ToString())
		m_pooling = con.ConnectionParameter("pooling", "True").ToString()
		m_rootIdentifier = String.Format("{0}@{1}#{2}", m_initialCatalog, m_dataSource, m_RecipeKey)
		DefaultShellDisplay = String.Format("OIM mirror ({2}) {0}@{1}", m_initialCatalog, m_dataSource, m_RecipeName)
		DefaultShellDescription = "Mirror of One Identity Manager v9.2 data into v10 (generic MSSQL connector, read-only, matching by UID)"
		LoadColumnMetadata()
	End Sub

	Private Sub LoadColumnMetadata()
		Dim dbCon As IConnection = DbSession.GetConnection()
		Dim f As ISqlFormatter = dbCon.SqlFormatter
		For Each tbl As String In m_Tables
			Dim uidTable = dbCon.GetSingleProperty("DialogTable", "UID_DialogTable", f.Comparison("TableName", tbl, ValType.String)).String
			Dim pk As New List(Of String)
			Dim crypted As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
			Dim cols As IColDbObject = dbCon.CreateCol("DialogColumn")
			cols.Prototype.WhereClause = f.Comparison("UID_DialogTable", uidTable, ValType.String)
			cols.Load()
			For Each ce As IColElem In cols
				Dim c As ISingleDbObject = ce.Create()
				Dim colName As String = c.GetValue("ColumnName").String
				If c.GetValue("IsPKMember").Bool Then pk.Add(colName)
				If c.GetValue("IsCrypted").Bool Then crypted.Add(colName)
			Next
			m_PkColumns(tbl) = pk
			m_CryptedColumns(tbl) = crypted

			' self references: FK columns of this table pointing to this same table
			Dim selfRef As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
			Dim rels As IColDbObject = dbCon.CreateCol("QBMRelation")
			rels.Prototype.WhereClause = "IsMNRelation = 0 AND UID_ChildColumn IN (SELECT UID_DialogColumn FROM DialogColumn WHERE UID_DialogTable = '" & uidTable & "') AND UID_ParentColumn IN (SELECT UID_DialogColumn FROM DialogColumn WHERE UID_DialogTable = '" & uidTable & "')"
			rels.Load()
			For Each re As IColElem In rels
				Dim r As ISingleDbObject = re.Create()
				Dim childCol = dbCon.GetSingleProperty("DialogColumn", "ColumnName", f.Comparison("UID_DialogColumn", r.GetValue("UID_ChildColumn").String, ValType.String)).String
				If Not pk.Contains(childCol, StringComparer.OrdinalIgnoreCase) Then selfRef.Add(childCol)
			Next
			m_SelfRefColumns(tbl) = selfRef
			Log(String.Format("{0}: PK={1}; crypted={2}; selfRef={3}", tbl, String.Join(",", pk), String.Join(",", crypted), String.Join(",", selfRef)))
		Next
	End Sub

	''' <summary>Root object (dummy UNSRootB) used to bind the project to a synchronization server.</summary>
	Protected Overrides Sub OnPrepareSystems()
		Log("=== OnPrepareSystems")
		Dim con As ISystemConnection = GetConnection("ConnectedSystemConnection")
		Dim dbCon As IConnection = DbSession.GetConnection()
		Dim f As ISqlFormatter = dbCon.SqlFormatter
		Dim objectsToSave = New List(Of ISingleDbObject)()

		Dim namespaceUID = dbCon.GetSingleProperty("DPRNameSpace", "UID_DPRNameSpace",
			f.Comparison("Ident_DPRNameSpace", m_TargetSystemType, ValType.String, CompareOperator.Equal, FormatterOptions.IgnoreCase)).String
		If String.IsNullOrEmpty(namespaceUID) Then
			Dim dbNameSpace As ISingleDbObject = dbCon.CreateSingle("DPRNameSpace")
			dbNameSpace("Ident_DPRNameSpace").NewValue = m_TargetSystemType
			dbNameSpace("DisplayName").NewValue = m_TargetSystemTypeDisplay
			namespaceUID = dbNameSpace.GetValue("UID_DPRNameSpace").String
			objectsToSave.Add(dbNameSpace)
		End If

		Dim rootUID = dbCon.GetSingleProperty("UNSRootB", "UID_UNSRootB", f.AndRelation(
			f.Comparison("CanonicalName", m_rootIdentifier, ValType.String),
			f.Comparison("UID_DPRNameSpace", namespaceUID, ValType.String))).String

		Dim root As ISingleDbObject
		If Not String.IsNullOrEmpty(rootUID) Then
			root = dbCon.CreateSingle("UNSRootB", rootUID)
		Else
			root = dbCon.CreateSingle("UNSRootB")
			root("Ident_UNSRoot").NewValue = "OIMMirror_" & root.GetValue("UID_UNSRootB").String.Replace("-"c, "_"c)
			root("DistinguishedName").NewValue = "oimmirror=" & m_rootIdentifier.Replace(",", "\,").Replace("=", "\=")
			root("CanonicalName").NewValue = m_rootIdentifier
			root("DisplayName").NewValue = "OIM v9.2 mirror (" & m_RecipeName & ") " & m_rootIdentifier
			root("NamespaceManagedBy").NewValue = "VISYNC"
			root("UID_DPRNameSpace").NewValue = namespaceUID
		End If
		objectsToSave.Add(root)

		Shell.AddSaveAction(Sub(theShell As IProjectorShell)
								For Each dbObj In objectsToSave
									dbObj.Save()
								Next
								Dim roci = dbCon.CreateSingle("DPRRootObjConnectionInfo")
								roci("ObjectKeyRoot").NewValue = root.GetValue("XObjectKey").String
								roci("UID_DPRSystemConnection").NewValue = con.Uid
								roci("UID_DPRSystemVariableSet").NewValue = theShell.DefaultVariableSet.Uid
								roci("UID_QBMServer").NewValue = TemplateData.UidJobService
								roci.Save()
							End Sub, False)
	End Sub

	Protected Overrides Iterator Function OnCreateUIPages() As IEnumerable(Of ITemplateUIPage)
		Return
	End Function

	Private Function FindRightType(rightSchema As ISchema, tbl As String) As ISchemaType
		For Each t As ISchemaType In rightSchema.Types
			If String.Equals(t.Name, tbl, StringComparison.OrdinalIgnoreCase) OrElse t.Name.EndsWith("." & tbl, StringComparison.OrdinalIgnoreCase) Then
				Return t
			End If
		Next
		Return Nothing
	End Function

	Private Function FindProperty(t As ISchemaType, name As String) As ISchemaProperty
		For Each p As ISchemaProperty In t.Properties
			If String.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase) Then Return p
		Next
		Return Nothing
	End Function

	Protected Overrides Sub OnCreateSystemMaps()
		Log("=== OnCreateSystemMaps")
		Dim leftSchema As ISchema = GetConnection("MainConnection").Schema
		Dim rightSchema As ISchema = GetConnection("ConnectedSystemConnection").Schema

		For Each tbl As String In m_Tables
			Try
				Dim leftType As ISchemaType = Nothing
				For Each t As ISchemaType In leftSchema.Types
					If String.Equals(t.Name, tbl, StringComparison.OrdinalIgnoreCase) Then leftType = t
				Next
				Dim rightType As ISchemaType = FindRightType(rightSchema, tbl)
				If leftType Is Nothing OrElse rightType Is Nothing Then
					Log(String.Format("SKIP {0}: left={1} right={2}", tbl, leftType IsNot Nothing, rightType IsNot Nothing))
					Continue For
				End If
				Log(String.Format("{0}: left class {1}, right type {2} class {3}", tbl, leftType.MasterClass.Name, rightType.Name, rightType.MasterClass.Name))

				Dim pk As List(Of String) = m_PkColumns(tbl)
				Dim crypted As HashSet(Of String) = m_CryptedColumns(tbl)
				Dim selfRef As HashSet(Of String) = m_SelfRefColumns(tbl)

				' main map
				Dim mapName As String = tbl
				Dim map = ShellUtils.AddMap(Shell, mapName, leftType.Name, rightType.Name, "Mirror " & tbl, SystemMappingDirection.ToTheLeft,
											leftType.MasterClass.Name, rightType.MasterClass.Name, SystemMapCapabilities.Default, False, mapName)
				Dim mapped As New List(Of String)
				Dim refCols As New List(Of String)
				Dim skipped As New List(Of String)
				For Each lp As ISchemaProperty In leftType.Properties
					Dim n As String = lp.Name
					If lp.IsVirtual OrElse m_ExcludedColumns.Contains(n) OrElse crypted.Contains(n) OrElse lp.IsSecretValue Then Continue For
					If lp.AccessConstraint = SchemaPropertyAccessConstraint.ReadOnly Then
						skipped.Add(n & "(ro)")
						Continue For
					End If
					If selfRef.Contains(n) OrElse (m_LateColumns.Contains(n) AndAlso Not pk.Contains(n, StringComparer.OrdinalIgnoreCase)) Then
						If FindProperty(rightType, n) IsNot Nothing Then refCols.Add(n)
						Continue For
					End If
					Dim rp As ISchemaProperty = FindProperty(rightType, n)
					If rp Is Nothing Then
						skipped.Add(n & "(no source)")
						Continue For
					End If
					If pk.Contains(n, StringComparer.OrdinalIgnoreCase) Then
						ShellUtils.AddKeyRule(map, n, rp.Name, True, "Key_" & n, "Key " & n, 0D)
					End If
					ShellUtils.AddMappingRuleToTheLeft(map, n, rp.Name, False, False, False, "R_" & n, n)
					mapped.Add(n)
				Next
				m_MapOrder.Add(mapName)
				Log(String.Format("{0}: mapped {1} columns; second step: {2}; skipped: {3}", tbl, mapped.Count, String.Join(",", refCols), String.Join(", ", skipped)))

				' second map for self references (filled after all objects exist)
				If refCols.Count > 0 Then
					Dim mapSelf As String = tbl & "_Refs"
					Dim map2 = ShellUtils.AddMap(Shell, mapSelf, leftType.Name, rightType.Name, "Mirror " & tbl & " references filled after all objects exist", SystemMappingDirection.ToTheLeft,
												 leftType.MasterClass.Name, rightType.MasterClass.Name, SystemMapCapabilities.Default, False, mapSelf)
					For Each k As String In pk
						Dim rk As ISchemaProperty = FindProperty(rightType, k)
						If rk IsNot Nothing Then ShellUtils.AddKeyRule(map2, k, rk.Name, True, "Key_" & k, "Key " & k, 0D)
					Next
					For Each sr As String In refCols
						Dim rp As ISchemaProperty = FindProperty(rightType, sr)
						If rp IsNot Nothing Then ShellUtils.AddMappingRuleToTheLeft(map2, sr, rp.Name, False, False, False, "R_" & sr, sr)
					Next
					m_SelfRefMaps.Add(mapSelf)
				End If
			Catch ex As Exception
				Log("ERROR map " & tbl & ": " & ex.ToString())
				Throw New ViException(2186022, ex, tbl)
			End Try
		Next
	End Sub
	Private m_SelfRefMaps As New List(Of String)

	Private Function FindMethod(t As ISchemaType, name As String) As ISchemaMethod
		For Each m As ISchemaMethod In t.Methods
			If String.Equals(m.Name, name, StringComparison.OrdinalIgnoreCase) Then Return m
		Next
		Log("no method " & name & " on " & t.Name)
		Return Nothing
	End Function

	Private Sub ConfigureStep(theStep As IProjectionStep)
		theStep.ProjectionDirection = ProjectionDirection.ToTheLeft
		Dim leftType = theStep.Map.SchemaClassLeft.SchemaType
		Dim isSelfRef As Boolean = theStep.Map.Name.EndsWith("_Refs")

		' objects only in v9.2 -> Insert (not for the self reference step)
		For Each m As ISchemaMethodAssignment In theStep.MatchingSets.DifferenceLeftToRight.LeftMethods.ToList()
			theStep.MatchingSets.DifferenceLeftToRight.LeftMethods.Remove(m.Name)
		Next
		If Not isSelfRef Then
			Dim mIns As ISchemaMethod = FindMethod(leftType, "Insert")
			If mIns IsNot Nothing Then theStep.MatchingSets.DifferenceLeftToRight.LeftMethods.Add(New SchemaMethodAssignment(mIns, ProjectionDirectionAssignment.ToLeft, ProjectionCondition.True))
		End If

		' objects in both -> Update
		For Each m As ISchemaMethodAssignment In theStep.MatchingSets.IntersectionWithDifferences.LeftMethods.ToList()
			theStep.MatchingSets.IntersectionWithDifferences.LeftMethods.Remove(m.Name)
		Next
		Dim mUpd As ISchemaMethod = FindMethod(leftType, "Update")
		If mUpd IsNot Nothing Then theStep.MatchingSets.IntersectionWithDifferences.LeftMethods.Add(New SchemaMethodAssignment(mUpd, ProjectionDirectionAssignment.ToLeft, ProjectionCondition.True))

		' objects only in v10 -> nothing in the daily run (deletes are a separate decision)
		For Each m As ISchemaMethodAssignment In theStep.MatchingSets.DifferenceRightToLeft.LeftMethods.ToList()
			theStep.MatchingSets.DifferenceRightToLeft.LeftMethods.Remove(m.Name)
		Next
	End Sub

	Protected Overrides Sub OnCreateProjectionConfigurations()
		Log("=== OnCreateProjectionConfigurations")
		Try
			Dim order As New List(Of String)(m_MapOrder)
			order.AddRange(m_SelfRefMaps)
			Dim wf = CreateInitialImportWorkflow(m_WorkflowNameMirror, m_WorkflowNameMirror, order.ToArray())
			wf.Description = "Daily mirror of v9.2 data into v10 (insert + update, no delete)"
			wf.ProjectionDirection = ProjectionDirection.ToTheLeft
			' CreateInitialImportWorkflow can emit more than one step per map: keep the first one only
			Dim seenMaps As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
			For Each s In wf.Steps.ToList()
				If seenMaps.Add(s.Map.Name) Then
					ConfigureStep(s)
				Else
					wf.Steps.Remove(s)
				End If
			Next
			Log("workflow steps: " & String.Join(", ", wf.Steps.Select(Function(x) x.Map.Name)))
			Shell.ProjectionConfigurations.Add(wf)
		Catch ex As Exception
			Log("ERROR workflow: " & ex.ToString())
			Throw New ViException(2186023, ex, m_WorkflowNameMirror)
		End Try
	End Sub

	Protected Overrides Sub OnDefineDefaultVariables(defaultSet As ISystemVariableSet)
		Dim con As ISystemConnection = GetConnection("ConnectedSystemConnection")

		Dim varPooling = New SystemVariable("CP_pooling", m_pooling, False)
		varPooling.DisplayName = "Pooling"
		con.ConnectionParameter.Add(New SystemConnectionParameter("pooling", varPooling.Name, False, True), True)
		defaultSet.Variables.Add(varPooling)

		Dim varPassword = New SystemVariable("CP_password", m_password, True)
		varPassword.DisplayName = "Password"
		varPassword.Description = "Password of the SQL login used to read the v9.2 database."
		con.ConnectionParameter.Add(New SystemConnectionParameter("password", varPassword.Name, False, True), True)
		defaultSet.Variables.Add(varPassword)

		Dim varDataSource = New SystemVariable("CP_data_source", m_dataSource, False)
		varDataSource.DisplayName = "Data Source"
		varDataSource.Description = "SQL Server hosting the v9.2 database."
		con.ConnectionParameter.Add(New SystemConnectionParameter("data source", varDataSource.Name, False, True), True)
		defaultSet.Variables.Add(varDataSource)

		Dim varInitialCatalog = New SystemVariable("CP_initial_catalog", m_initialCatalog, False)
		varInitialCatalog.DisplayName = "Initial Catalog"
		varInitialCatalog.Description = "Name of the v9.2 database."
		con.ConnectionParameter.Add(New SystemConnectionParameter("initial catalog", varInitialCatalog.Name, False, True), True)
		defaultSet.Variables.Add(varInitialCatalog)

		Dim varUserId = New SystemVariable("CP_user_id", m_user_id, False)
		varUserId.DisplayName = "User"
		varUserId.Description = "SQL login used to read the v9.2 database (db_datareader)."
		con.ConnectionParameter.Add(New SystemConnectionParameter("user id", varUserId.Name, False, True), True)
		defaultSet.Variables.Add(varUserId)
	End Sub

	Protected Overrides Sub OnCreateSystemVariableSets()
		Return
	End Sub

	Private m_SourceScope As SystemScopeDefinition

	Protected Overrides Sub OnCreateScopes()
		If m_SourceFilters.Count = 0 Then Return
		Dim rightSchema As ISchema = GetConnection("ConnectedSystemConnection").Schema
		Dim scope = New SystemScopeDefinition("_sourcescope", "Source scope (v9.2)", rightSchema)
		For Each kv In m_SourceFilters
			Dim t As ISchemaType = FindRightType(rightSchema, kv.Key)
			If t Is Nothing Then Continue For
			Dim flt = New VI.Projector.Filter.SystemObjectFilterJoin(New VI.Projector.Filter.SystemObjectNativeSystemFilter(kv.Value),
				VI.Projector.Filter.SystemObjectDataFilter.Default, VI.Projector.Filter.SystemObjectFilter.Default)
			Dim sf = New SystemScopeFilter(t, flt)
			sf.DisplayName = kv.Key
			scope.SetFilter(sf)
			Log("source filter " & t.Name & ": " & kv.Value)
		Next
		scope.GlobalHierarchyFilter = VI.Projector.Filter.HierarchyFilter.Default
		Shell.Scopes.Add(scope)
		m_SourceScope = scope
	End Sub

	Protected Overrides Sub OnCreateProjectionStartInfos()
		Dim si = New VI.Projector.Projection.ProjectionStartInfo()
		si.DisplayName = String.Format("Mirror v9.2 ({2}) {0}@{1}", m_initialCatalog, m_dataSource, m_RecipeName)
		si.DefaultProjectionDirection = VI.Projector.Projection.ProjectionDirection.ToTheLeft
		si.VariableSet = Shell.DefaultVariableSet
		si.Schedule = DatabaseHelper.CreateDefaultSynchonizationSchedule(DbSession, Shell, si)
		si.Group.ConcurrenceBehavior = VI.Projector.Projection.StartGroupConcurrenceBehavior.Ignore
		si.ProjectionConfiguration = Shell.ProjectionConfigurations(m_WorkflowNameMirror)
		Shell.StartInfos.Add(si)
	End Sub

	Protected Overrides Sub OnExtentSchemas()
		Return
	End Sub

	Protected Overrides Sub OnPostProcessing()
		If m_SourceScope IsNot Nothing Then
			Shell.Connections("ConnectedSystemConnection").Scope.Definition = m_SourceScope
		End If
		Log("=== OnPostProcessing done")
	End Sub

	Protected Overrides ReadOnly Iterator Property RequiredSchemas As IEnumerable(Of String)
		Get
			Yield "Type=OneIM"
			Yield "Type=DB"
			Return
		End Get
	End Property

'@ }
$templates += [pscustomobject]@{ Uid = 'CCC-0D1A2B3C4D5E4F60A1B2C3D4E5F60719'; Name = 'OIM v9.2 to v10 mirror (Active Directory)'; Code = @'
References VI.Parsers.dll
References VI.TSUtils.dll
References VI.DB.dll
References VI.Projector.Database.dll
References VI.Projector.Database.Native.dll
References System.Xml.dll
References System.Xml.Linq.dll
References System.Core.dll

Imports VI.Projector
Imports VI.Projector.Projection
Imports VI.Projector.Database
Imports VI.Projector.Connection.Scope
Imports VI.Projector.Filter
Imports VI.Projector.Schema
Imports VI.Projector.Mapping.Rules
Imports VI.Projector.Mapping
Imports VI.Base
Imports VI.DB.Compatibility
Imports VI.DB
Imports VI.Projector.Connection
Imports VI.Projector.Scripting
Imports VI.Projector.Variables
Imports VI.DB.Entities
Imports VI.Parsers.Conditions
Imports VI.Projector.Templates

Imports System
Imports System.Collections.Generic
Imports System.Linq
Imports System.Text

	' ============================================================================
	' OIM v9.2 -> v10 mirror template
	' Left  = MainConnection (this One Identity Manager v10 database)
	' Right = ConnectedSystemConnection (generic MSSQL connector on the v9.2 database, read-only)
	' Matching by primary key (UID / UID pair), direction: to One Identity Manager only.
	' ============================================================================

	' ---- configuration: tables in workflow order ----
	Private Const m_RecipeKey As String = "ADS"
	Private Const m_RecipeName As String = "Active Directory"
	Private ReadOnly m_Tables As String() = {"ADSForest", "ADSDomain", "ADSContainer", "ADSGroup", "ADSGroupInADSGroup", "ADSAccount", "ADSAccountInADSGroup", "ADSContact", "ADSMachine", "ADSContactInADSGroup", "ADSMachineInADSGroup", "OrgHasADSGroup", "DepartmentHasADSGroup", "LocalityHasADSGroup", "ProfitCenterHasADSGroup", "AERoleHasADSGroup", "ITShopOrgHasADSGroup", "ITShopSrcHasADSGroup", "MirrorShopHasADSGroup", "ESetHasEntitlement"}

	' ---- reference columns filled in a second step (<Table>_Refs), so the objects they point to
	'      can be migrated later (IT Shop products, owners, servers, hardware) ----
	Private ReadOnly m_LateColumns As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)  From {"UID_AccProduct", "UID_AERoleOwner", "UID_Hardware", "UID_HomeServer", "UID_ProfileServer", "UID_TerminalHomeServer", "UID_TerminalProfileServer"}

	' ---- source (v9.2) scope filters: table -> SQL condition ----
	Private ReadOnly m_SourceFilters As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)  From {{"ESetHasEntitlement", "Entitlement LIKE '<Key><T>ADSGroup</T>%'"}}

	' ---- columns never mapped ----
	Private ReadOnly m_ExcludedColumns As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
		"XObjectKey", "XDateInserted", "XDateUpdated", "XUserInserted", "XUserUpdated",
		"XTouched", "XDateSubItem", "XMarkedForDeletion", "XOrigin", "XIsInEffect", "RiskIndexCalculated"}

	Private Const m_TargetSystemType As String = "OIMMIRROR"
	Private Const m_TargetSystemTypeDisplay As String = "OIM v9.2 mirror"
	Private ReadOnly m_WorkflowNameMirror As String = "Mirror v9.2 to v10 (" & m_RecipeName & ")"
	Private ReadOnly m_LogFile As String = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "OIMMirror-template-log.txt")

	Private m_user_id As String
	Private m_dataSource As String
	Private m_initialCatalog As String
	Private m_password As String
	Private m_pooling As String
	Private m_rootIdentifier As String

	' table -> PK columns, crypted columns, self reference columns (from DialogColumn / QBMRelation of v10)
	Private m_PkColumns As New Dictionary(Of String, List(Of String))(StringComparer.OrdinalIgnoreCase)
	Private m_CryptedColumns As New Dictionary(Of String, HashSet(Of String))(StringComparer.OrdinalIgnoreCase)
	Private m_SelfRefColumns As New Dictionary(Of String, HashSet(Of String))(StringComparer.OrdinalIgnoreCase)
	Private m_MapOrder As New List(Of String)

	Public Property DbSession As ISession
		Get
			Return m_DbSession
		End Get
		Private Set(value As ISession)
			m_DbSession = value
		End Set
	End Property
	Private m_DbSession As ISession

	Public Overrides ReadOnly Property Capabilities As ShellScriptCapabilities
		Get
			Return ShellScriptCapabilities.Default
		End Get
	End Property

	Private Sub Log(msg As String)
		Try
			System.IO.File.AppendAllText(m_LogFile, DateTime.Now.ToString("s") & " " & msg & Environment.NewLine)
		Catch
		End Try
	End Sub

	Protected Overrides Sub OnPreProcessing()
		Log("=== OnPreProcessing")
		Dim con As ISystemConnection = GetConnection("ConnectedSystemConnection")
		m_dataSource = con.ConnectionParameter("data source", "").ToString()
		m_initialCatalog = con.ConnectionParameter("initial catalog", "").ToString()
		m_user_id = SystemVariable.Unmask(con.ConnectionParameter("user id", "").ToString())
		m_password = SystemVariable.Unmask(con.ConnectionParameter("password", "").ToString())
		m_pooling = con.ConnectionParameter("pooling", "True").ToString()
		m_rootIdentifier = String.Format("{0}@{1}#{2}", m_initialCatalog, m_dataSource, m_RecipeKey)
		DefaultShellDisplay = String.Format("OIM mirror ({2}) {0}@{1}", m_initialCatalog, m_dataSource, m_RecipeName)
		DefaultShellDescription = "Mirror of One Identity Manager v9.2 data into v10 (generic MSSQL connector, read-only, matching by UID)"
		LoadColumnMetadata()
	End Sub

	Private Sub LoadColumnMetadata()
		Dim dbCon As IConnection = DbSession.GetConnection()
		Dim f As ISqlFormatter = dbCon.SqlFormatter
		For Each tbl As String In m_Tables
			Dim uidTable = dbCon.GetSingleProperty("DialogTable", "UID_DialogTable", f.Comparison("TableName", tbl, ValType.String)).String
			Dim pk As New List(Of String)
			Dim crypted As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
			Dim cols As IColDbObject = dbCon.CreateCol("DialogColumn")
			cols.Prototype.WhereClause = f.Comparison("UID_DialogTable", uidTable, ValType.String)
			cols.Load()
			For Each ce As IColElem In cols
				Dim c As ISingleDbObject = ce.Create()
				Dim colName As String = c.GetValue("ColumnName").String
				If c.GetValue("IsPKMember").Bool Then pk.Add(colName)
				If c.GetValue("IsCrypted").Bool Then crypted.Add(colName)
			Next
			m_PkColumns(tbl) = pk
			m_CryptedColumns(tbl) = crypted

			' self references: FK columns of this table pointing to this same table
			Dim selfRef As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
			Dim rels As IColDbObject = dbCon.CreateCol("QBMRelation")
			rels.Prototype.WhereClause = "IsMNRelation = 0 AND UID_ChildColumn IN (SELECT UID_DialogColumn FROM DialogColumn WHERE UID_DialogTable = '" & uidTable & "') AND UID_ParentColumn IN (SELECT UID_DialogColumn FROM DialogColumn WHERE UID_DialogTable = '" & uidTable & "')"
			rels.Load()
			For Each re As IColElem In rels
				Dim r As ISingleDbObject = re.Create()
				Dim childCol = dbCon.GetSingleProperty("DialogColumn", "ColumnName", f.Comparison("UID_DialogColumn", r.GetValue("UID_ChildColumn").String, ValType.String)).String
				If Not pk.Contains(childCol, StringComparer.OrdinalIgnoreCase) Then selfRef.Add(childCol)
			Next
			m_SelfRefColumns(tbl) = selfRef
			Log(String.Format("{0}: PK={1}; crypted={2}; selfRef={3}", tbl, String.Join(",", pk), String.Join(",", crypted), String.Join(",", selfRef)))
		Next
	End Sub

	''' <summary>Root object (dummy UNSRootB) used to bind the project to a synchronization server.</summary>
	Protected Overrides Sub OnPrepareSystems()
		Log("=== OnPrepareSystems")
		Dim con As ISystemConnection = GetConnection("ConnectedSystemConnection")
		Dim dbCon As IConnection = DbSession.GetConnection()
		Dim f As ISqlFormatter = dbCon.SqlFormatter
		Dim objectsToSave = New List(Of ISingleDbObject)()

		Dim namespaceUID = dbCon.GetSingleProperty("DPRNameSpace", "UID_DPRNameSpace",
			f.Comparison("Ident_DPRNameSpace", m_TargetSystemType, ValType.String, CompareOperator.Equal, FormatterOptions.IgnoreCase)).String
		If String.IsNullOrEmpty(namespaceUID) Then
			Dim dbNameSpace As ISingleDbObject = dbCon.CreateSingle("DPRNameSpace")
			dbNameSpace("Ident_DPRNameSpace").NewValue = m_TargetSystemType
			dbNameSpace("DisplayName").NewValue = m_TargetSystemTypeDisplay
			namespaceUID = dbNameSpace.GetValue("UID_DPRNameSpace").String
			objectsToSave.Add(dbNameSpace)
		End If

		Dim rootUID = dbCon.GetSingleProperty("UNSRootB", "UID_UNSRootB", f.AndRelation(
			f.Comparison("CanonicalName", m_rootIdentifier, ValType.String),
			f.Comparison("UID_DPRNameSpace", namespaceUID, ValType.String))).String

		Dim root As ISingleDbObject
		If Not String.IsNullOrEmpty(rootUID) Then
			root = dbCon.CreateSingle("UNSRootB", rootUID)
		Else
			root = dbCon.CreateSingle("UNSRootB")
			root("Ident_UNSRoot").NewValue = "OIMMirror_" & root.GetValue("UID_UNSRootB").String.Replace("-"c, "_"c)
			root("DistinguishedName").NewValue = "oimmirror=" & m_rootIdentifier.Replace(",", "\,").Replace("=", "\=")
			root("CanonicalName").NewValue = m_rootIdentifier
			root("DisplayName").NewValue = "OIM v9.2 mirror (" & m_RecipeName & ") " & m_rootIdentifier
			root("NamespaceManagedBy").NewValue = "VISYNC"
			root("UID_DPRNameSpace").NewValue = namespaceUID
		End If
		objectsToSave.Add(root)

		Shell.AddSaveAction(Sub(theShell As IProjectorShell)
								For Each dbObj In objectsToSave
									dbObj.Save()
								Next
								Dim roci = dbCon.CreateSingle("DPRRootObjConnectionInfo")
								roci("ObjectKeyRoot").NewValue = root.GetValue("XObjectKey").String
								roci("UID_DPRSystemConnection").NewValue = con.Uid
								roci("UID_DPRSystemVariableSet").NewValue = theShell.DefaultVariableSet.Uid
								roci("UID_QBMServer").NewValue = TemplateData.UidJobService
								roci.Save()
							End Sub, False)
	End Sub

	Protected Overrides Iterator Function OnCreateUIPages() As IEnumerable(Of ITemplateUIPage)
		Return
	End Function

	Private Function FindRightType(rightSchema As ISchema, tbl As String) As ISchemaType
		For Each t As ISchemaType In rightSchema.Types
			If String.Equals(t.Name, tbl, StringComparison.OrdinalIgnoreCase) OrElse t.Name.EndsWith("." & tbl, StringComparison.OrdinalIgnoreCase) Then
				Return t
			End If
		Next
		Return Nothing
	End Function

	Private Function FindProperty(t As ISchemaType, name As String) As ISchemaProperty
		For Each p As ISchemaProperty In t.Properties
			If String.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase) Then Return p
		Next
		Return Nothing
	End Function

	Protected Overrides Sub OnCreateSystemMaps()
		Log("=== OnCreateSystemMaps")
		Dim leftSchema As ISchema = GetConnection("MainConnection").Schema
		Dim rightSchema As ISchema = GetConnection("ConnectedSystemConnection").Schema

		For Each tbl As String In m_Tables
			Try
				Dim leftType As ISchemaType = Nothing
				For Each t As ISchemaType In leftSchema.Types
					If String.Equals(t.Name, tbl, StringComparison.OrdinalIgnoreCase) Then leftType = t
				Next
				Dim rightType As ISchemaType = FindRightType(rightSchema, tbl)
				If leftType Is Nothing OrElse rightType Is Nothing Then
					Log(String.Format("SKIP {0}: left={1} right={2}", tbl, leftType IsNot Nothing, rightType IsNot Nothing))
					Continue For
				End If
				Log(String.Format("{0}: left class {1}, right type {2} class {3}", tbl, leftType.MasterClass.Name, rightType.Name, rightType.MasterClass.Name))

				Dim pk As List(Of String) = m_PkColumns(tbl)
				Dim crypted As HashSet(Of String) = m_CryptedColumns(tbl)
				Dim selfRef As HashSet(Of String) = m_SelfRefColumns(tbl)

				' main map
				Dim mapName As String = tbl
				Dim map = ShellUtils.AddMap(Shell, mapName, leftType.Name, rightType.Name, "Mirror " & tbl, SystemMappingDirection.ToTheLeft,
											leftType.MasterClass.Name, rightType.MasterClass.Name, SystemMapCapabilities.Default, False, mapName)
				Dim mapped As New List(Of String)
				Dim refCols As New List(Of String)
				Dim skipped As New List(Of String)
				For Each lp As ISchemaProperty In leftType.Properties
					Dim n As String = lp.Name
					If lp.IsVirtual OrElse m_ExcludedColumns.Contains(n) OrElse crypted.Contains(n) OrElse lp.IsSecretValue Then Continue For
					If lp.AccessConstraint = SchemaPropertyAccessConstraint.ReadOnly Then
						skipped.Add(n & "(ro)")
						Continue For
					End If
					If selfRef.Contains(n) OrElse (m_LateColumns.Contains(n) AndAlso Not pk.Contains(n, StringComparer.OrdinalIgnoreCase)) Then
						If FindProperty(rightType, n) IsNot Nothing Then refCols.Add(n)
						Continue For
					End If
					Dim rp As ISchemaProperty = FindProperty(rightType, n)
					If rp Is Nothing Then
						skipped.Add(n & "(no source)")
						Continue For
					End If
					If pk.Contains(n, StringComparer.OrdinalIgnoreCase) Then
						ShellUtils.AddKeyRule(map, n, rp.Name, True, "Key_" & n, "Key " & n, 0D)
					End If
					ShellUtils.AddMappingRuleToTheLeft(map, n, rp.Name, False, False, False, "R_" & n, n)
					mapped.Add(n)
				Next
				m_MapOrder.Add(mapName)
				Log(String.Format("{0}: mapped {1} columns; second step: {2}; skipped: {3}", tbl, mapped.Count, String.Join(",", refCols), String.Join(", ", skipped)))

				' second map for self references (filled after all objects exist)
				If refCols.Count > 0 Then
					Dim mapSelf As String = tbl & "_Refs"
					Dim map2 = ShellUtils.AddMap(Shell, mapSelf, leftType.Name, rightType.Name, "Mirror " & tbl & " references filled after all objects exist", SystemMappingDirection.ToTheLeft,
												 leftType.MasterClass.Name, rightType.MasterClass.Name, SystemMapCapabilities.Default, False, mapSelf)
					For Each k As String In pk
						Dim rk As ISchemaProperty = FindProperty(rightType, k)
						If rk IsNot Nothing Then ShellUtils.AddKeyRule(map2, k, rk.Name, True, "Key_" & k, "Key " & k, 0D)
					Next
					For Each sr As String In refCols
						Dim rp As ISchemaProperty = FindProperty(rightType, sr)
						If rp IsNot Nothing Then ShellUtils.AddMappingRuleToTheLeft(map2, sr, rp.Name, False, False, False, "R_" & sr, sr)
					Next
					m_SelfRefMaps.Add(mapSelf)
				End If
			Catch ex As Exception
				Log("ERROR map " & tbl & ": " & ex.ToString())
				Throw New ViException(2186022, ex, tbl)
			End Try
		Next
	End Sub
	Private m_SelfRefMaps As New List(Of String)

	Private Function FindMethod(t As ISchemaType, name As String) As ISchemaMethod
		For Each m As ISchemaMethod In t.Methods
			If String.Equals(m.Name, name, StringComparison.OrdinalIgnoreCase) Then Return m
		Next
		Log("no method " & name & " on " & t.Name)
		Return Nothing
	End Function

	Private Sub ConfigureStep(theStep As IProjectionStep)
		theStep.ProjectionDirection = ProjectionDirection.ToTheLeft
		Dim leftType = theStep.Map.SchemaClassLeft.SchemaType
		Dim isSelfRef As Boolean = theStep.Map.Name.EndsWith("_Refs")

		' objects only in v9.2 -> Insert (not for the self reference step)
		For Each m As ISchemaMethodAssignment In theStep.MatchingSets.DifferenceLeftToRight.LeftMethods.ToList()
			theStep.MatchingSets.DifferenceLeftToRight.LeftMethods.Remove(m.Name)
		Next
		If Not isSelfRef Then
			Dim mIns As ISchemaMethod = FindMethod(leftType, "Insert")
			If mIns IsNot Nothing Then theStep.MatchingSets.DifferenceLeftToRight.LeftMethods.Add(New SchemaMethodAssignment(mIns, ProjectionDirectionAssignment.ToLeft, ProjectionCondition.True))
		End If

		' objects in both -> Update
		For Each m As ISchemaMethodAssignment In theStep.MatchingSets.IntersectionWithDifferences.LeftMethods.ToList()
			theStep.MatchingSets.IntersectionWithDifferences.LeftMethods.Remove(m.Name)
		Next
		Dim mUpd As ISchemaMethod = FindMethod(leftType, "Update")
		If mUpd IsNot Nothing Then theStep.MatchingSets.IntersectionWithDifferences.LeftMethods.Add(New SchemaMethodAssignment(mUpd, ProjectionDirectionAssignment.ToLeft, ProjectionCondition.True))

		' objects only in v10 -> nothing in the daily run (deletes are a separate decision)
		For Each m As ISchemaMethodAssignment In theStep.MatchingSets.DifferenceRightToLeft.LeftMethods.ToList()
			theStep.MatchingSets.DifferenceRightToLeft.LeftMethods.Remove(m.Name)
		Next
	End Sub

	Protected Overrides Sub OnCreateProjectionConfigurations()
		Log("=== OnCreateProjectionConfigurations")
		Try
			Dim order As New List(Of String)(m_MapOrder)
			order.AddRange(m_SelfRefMaps)
			Dim wf = CreateInitialImportWorkflow(m_WorkflowNameMirror, m_WorkflowNameMirror, order.ToArray())
			wf.Description = "Daily mirror of v9.2 data into v10 (insert + update, no delete)"
			wf.ProjectionDirection = ProjectionDirection.ToTheLeft
			' CreateInitialImportWorkflow can emit more than one step per map: keep the first one only
			Dim seenMaps As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
			For Each s In wf.Steps.ToList()
				If seenMaps.Add(s.Map.Name) Then
					ConfigureStep(s)
				Else
					wf.Steps.Remove(s)
				End If
			Next
			Log("workflow steps: " & String.Join(", ", wf.Steps.Select(Function(x) x.Map.Name)))
			Shell.ProjectionConfigurations.Add(wf)
		Catch ex As Exception
			Log("ERROR workflow: " & ex.ToString())
			Throw New ViException(2186023, ex, m_WorkflowNameMirror)
		End Try
	End Sub

	Protected Overrides Sub OnDefineDefaultVariables(defaultSet As ISystemVariableSet)
		Dim con As ISystemConnection = GetConnection("ConnectedSystemConnection")

		Dim varPooling = New SystemVariable("CP_pooling", m_pooling, False)
		varPooling.DisplayName = "Pooling"
		con.ConnectionParameter.Add(New SystemConnectionParameter("pooling", varPooling.Name, False, True), True)
		defaultSet.Variables.Add(varPooling)

		Dim varPassword = New SystemVariable("CP_password", m_password, True)
		varPassword.DisplayName = "Password"
		varPassword.Description = "Password of the SQL login used to read the v9.2 database."
		con.ConnectionParameter.Add(New SystemConnectionParameter("password", varPassword.Name, False, True), True)
		defaultSet.Variables.Add(varPassword)

		Dim varDataSource = New SystemVariable("CP_data_source", m_dataSource, False)
		varDataSource.DisplayName = "Data Source"
		varDataSource.Description = "SQL Server hosting the v9.2 database."
		con.ConnectionParameter.Add(New SystemConnectionParameter("data source", varDataSource.Name, False, True), True)
		defaultSet.Variables.Add(varDataSource)

		Dim varInitialCatalog = New SystemVariable("CP_initial_catalog", m_initialCatalog, False)
		varInitialCatalog.DisplayName = "Initial Catalog"
		varInitialCatalog.Description = "Name of the v9.2 database."
		con.ConnectionParameter.Add(New SystemConnectionParameter("initial catalog", varInitialCatalog.Name, False, True), True)
		defaultSet.Variables.Add(varInitialCatalog)

		Dim varUserId = New SystemVariable("CP_user_id", m_user_id, False)
		varUserId.DisplayName = "User"
		varUserId.Description = "SQL login used to read the v9.2 database (db_datareader)."
		con.ConnectionParameter.Add(New SystemConnectionParameter("user id", varUserId.Name, False, True), True)
		defaultSet.Variables.Add(varUserId)
	End Sub

	Protected Overrides Sub OnCreateSystemVariableSets()
		Return
	End Sub

	Private m_SourceScope As SystemScopeDefinition

	Protected Overrides Sub OnCreateScopes()
		If m_SourceFilters.Count = 0 Then Return
		Dim rightSchema As ISchema = GetConnection("ConnectedSystemConnection").Schema
		Dim scope = New SystemScopeDefinition("_sourcescope", "Source scope (v9.2)", rightSchema)
		For Each kv In m_SourceFilters
			Dim t As ISchemaType = FindRightType(rightSchema, kv.Key)
			If t Is Nothing Then Continue For
			Dim flt = New VI.Projector.Filter.SystemObjectFilterJoin(New VI.Projector.Filter.SystemObjectNativeSystemFilter(kv.Value),
				VI.Projector.Filter.SystemObjectDataFilter.Default, VI.Projector.Filter.SystemObjectFilter.Default)
			Dim sf = New SystemScopeFilter(t, flt)
			sf.DisplayName = kv.Key
			scope.SetFilter(sf)
			Log("source filter " & t.Name & ": " & kv.Value)
		Next
		scope.GlobalHierarchyFilter = VI.Projector.Filter.HierarchyFilter.Default
		Shell.Scopes.Add(scope)
		m_SourceScope = scope
	End Sub

	Protected Overrides Sub OnCreateProjectionStartInfos()
		Dim si = New VI.Projector.Projection.ProjectionStartInfo()
		si.DisplayName = String.Format("Mirror v9.2 ({2}) {0}@{1}", m_initialCatalog, m_dataSource, m_RecipeName)
		si.DefaultProjectionDirection = VI.Projector.Projection.ProjectionDirection.ToTheLeft
		si.VariableSet = Shell.DefaultVariableSet
		si.Schedule = DatabaseHelper.CreateDefaultSynchonizationSchedule(DbSession, Shell, si)
		si.Group.ConcurrenceBehavior = VI.Projector.Projection.StartGroupConcurrenceBehavior.Ignore
		si.ProjectionConfiguration = Shell.ProjectionConfigurations(m_WorkflowNameMirror)
		Shell.StartInfos.Add(si)
	End Sub

	Protected Overrides Sub OnExtentSchemas()
		Return
	End Sub

	Protected Overrides Sub OnPostProcessing()
		If m_SourceScope IsNot Nothing Then
			Shell.Connections("ConnectedSystemConnection").Scope.Definition = m_SourceScope
		End If
		Log("=== OnPostProcessing done")
	End Sub

	Protected Overrides ReadOnly Iterator Property RequiredSchemas As IEnumerable(Of String)
		Get
			Yield "Type=OneIM"
			Yield "Type=DB"
			Return
		End Get
	End Property

'@ }

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
