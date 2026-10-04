#If Not SCRIPTDEBUGGER Then
References VI.DataImport.dll

Imports System.Collections.Generic
Imports System.IO
Imports System.Globalization
Imports VI.DB.Entities
Imports VI.DB.Specialized
Imports VI.DataImport
#End If

#If EBS Then
    ' in case of ImportSource EBS% delete is not permitted
    If CStr($ImportSource$).StartsWith("EBS") AndAlso $[IsDeleted]:Bool$ Then
        If Not CBool(Connection.Variables("ManageOutstanding")) Then
            'delete is allowed only in the formular DPR_ManageOutstanding (FormDPRManageOutstanding)
            Throw New ViException(#LD("Deletion of data who are managed in Oracle E-Business is not allowed.")#, ExceptionRelevance.EndUser)
        End If
    End If
#End If

#If SAPR3HRPROFILE Then
    ' in case of ImportSource SAP delete is not permitted
    If CStr($ImportSource$).StartsWith("SAP") AndAlso $[IsDeleted]:Bool$ Then
        If Not CBool(Connection.Variables("ManageOutstanding")) Then
            'delete is allowed only in the formular DPR_ManageOutstanding (FormDPRManageOutstanding)
            Throw New ViException(#LD("Deletion of data who are managed in SAP HCM is not allowed.")#, ExceptionRelevance.EndUser)
        End If
    End If
#End If

If (Not $[IsDeleted]:Bool$) And CBool($CustomProperty01[c]$) _
    And $CustomProperty01[o]$.ToString.Length > 1 And $CustomProperty01$ = "BuildingAccessOnlyVendor"  Then
    Throw New ViException(#LD("Changing an existing user to 'BuildingAccessOnlyVendor' is not allowed.")#, ExceptionRelevance.EndUser)
End If


Dim endpointType As String = $CCC_SourceEndpoint$
Dim futureEndpoint As String = "FUTURE"
Dim mainEndpoint As String = "MAIN"

If CBool(Connection.Variables("Projection")) _
    And Not CBool(Connection.Variables("FULLSYNC")) _
    And $CCC_IsMasterIdentity:Bool$ _
    And $ImportSource$="WORKDAY" _
    And (Not $CCC_SourceEndpoint$.Equals("WIDSWITCH")) Then 'This section needs to happen only when running Data Import sync from Workday through Starling Connector
    Dim logFile = Connection.GetConfigParm("Custom\HR\LogFileDirectory") & "\" & String.Format("Person_OnSaving_{0}_{1}.log",endpointType,Date.Now.ToString("MM-dd-yyyy"))
    Dim timestamp As String=Date.Now.ToString("MM-dd-yyyy hh:mm:ss tt")
    vid_write2log(logFile, String.Format("0-Person ONSAVING: endpoint: {0} - Sourceendpoint: {1} - workdayWID: {2} - workdayID: {3} - uidPerson: {4} ",endpointType,$CCC_SourceEndpoint$,$CCC_WorkdayID$,$CCC_Workday_EmployeeID$,$UID_Person$))
    Dim isInvalidNewHire As Boolean= Not $[IsLoaded]:Bool$ AndAlso 'Empty EmployeeID means it's a new identiy //IsLoaded
                                     (($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L") AndAlso ' active
                                     $EntryDate:Date$ < CDate(Date.Now.ToShortDateString)) AndAlso 'StartDate is in the past
                                     String.IsNullOrEmpty($CCC_LatestWorkerWID$) 'Sai: scenario with duplicates is excluded from this check
    If(isInvalidNewHire) Then
        vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Invalid New Hire - New Hire received active with past start date"))
        Throw New ViException(#LD("Worker Import Validation failed: Invalid New Hire: Hire received with past start date.")#, ExceptionRelevance.EndUser)
    End If
    'Future Validation Start
    If endpointType.Equals(futureEndpoint) Then
        vid_write2log(logFile, String.Format("1-insideFUTUREEndpoint: endpoint: {0} - Sourceendpoint: {1} - workdayWID: {2} - workdayID: {3} - uidPerson: {4} ",endpointType,$CCC_SourceEndpoint$,$CCC_WorkdayID$,$CCC_Workday_EmployeeID$,$UID_Person$))

        Dim isInactiveNewHire As Boolean= Not $[IsLoaded]:Bool$ AndAlso 'Empty EmployeeID means it's a new identiy //IsLoaded
                                          Not ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L") ' Not active

        Dim isInvalidRehire As Boolean = $CCC_Rehire:Bool$ AndAlso 'RehireFlag is changing to 1
                                         $EntryDate:Date$ < CDate(Date.Now.ToShortDateString) AndAlso 'EntryDate is in the past
                                         $IsInActive[o]:Bool$ AndAlso 'Previously Inactive
                                         ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L") 'Now it will be active

        Dim NoValidEmailLogOnly As Boolean = ($EmployeeType$="Visitor" Or $EmployeeType$="Employee") AndAlso
                                             (String.IsNullOrEmpty($CCC_AlternateEmail$) Or String.IsNullOrEmpty($CCC_Personal_Email$))

        Dim isInvalidNewContractor As Boolean= $EmployeeType$="Visitor" AndAlso
                                               (String.IsNullOrEmpty($CCC_Personal_Email$) Or $CCC_Personal_Email$.ToUpper()="WORKDAY_DEFAULT") AndAlso
                                               (String.IsNullOrEmpty($CCC_AlternateEmail$) Or $CCC_AlternateEmail$.ToUpper()="WORKDAY_DEFAULT") AndAlso
                                               Not $CCC_Email_Required:Bool$ AndAlso
                                               (Not String.IsNullOrEmpty($CCC_Workday_Status$) AndAlso ($CCC_Workday_Status$.ToUpper()="A" Or $CCC_Workday_Status$.ToUpper()="L")) AndAlso
                                               $EntryDate:Date$ >= CDate(Date.Now.ToShortDateString)

        If(NoValidEmailLogOnly) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: New Employee or Visitor - no personal or alternate email"))
        End If

        If(isInactiveNewHire) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Inactive New Hire - New Hire received inactive"))
            Throw New ViException(#LD("Worker Import Validation failed: Inactive New Hire")#, ExceptionRelevance.EndUser)
        End If

        If(isInvalidRehire) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Invalid Rehire - Rehire flag modification to 1 with the start date in the past"))
            Throw New ViException(#LD("Worker Import Validation failed: Invalid Rehire")#, ExceptionRelevance.EndUser)
        End If

        If(isInvalidNewContractor) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Invalid Contractor data - Contractor received with no personal email and alternate email. At least one personal email is required when contractor does not get fhlbc email. Please reach out to HR to capture the email."))
            'Throw New ViException(#LD("Worker Import Validation failed: Invalid Contractor data")#, ExceptionRelevance.EndUser)
        End If

        'filter any inactive duplicate record that show up excluding rescinds
        If $CCC_Workday_Status$.ToUpper() = "I" _
            And (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
            And (Not $CCC_New_Hire_Rescind:Bool$) Then

            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - Skipping the inactive account from future end point - object was not saved to Person table.",$CCC_Workday_EmployeeID$)))
            Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - Skipping the inactive account from Future end point - object was not saved to Person table.",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)
        'filter any inactive records - just a cautionary check
        Else If $CCC_Workday_Status$.ToUpper() = "I" _
            And String.IsNullOrEmpty($CCC_LatestWorkerWID$) _
                And (Not $CCC_New_Hire_Rescind:Bool$) Then

            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,String.Format("WorkerID Found: {0} -  Skipping the account. We do not expect inactive accounts in future end point - object was not saved to Person table.",$CCC_Workday_EmployeeID$)))
            Throw New ViException(String.Format("Inactive WorkerID Found in Future End Point: {0} - Skipping the inactive account from Future end point - object was not saved to Person table.",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)
        End If

        If $CCC_Workday_Status$.ToUpper() = "I" _
            AndAlso $CCC_New_Hire_Rescind:Bool$ _
            AndAlso $[IsLoaded]:Bool$ Then
            'All good new hire rescind scenario
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("NewHire Rescinded WorkerID Found: {0} - Processed New Hire Rescind record .",$CCC_Workday_EmployeeID$)))
        Else If ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L" ) _
            AndAlso String.IsNullOrEmpty($CCC_LatestWorkerWID$) _
            AndAlso (Not $CCC_Rehire:Bool$) _
            AndAlso $EntryDate:Date$ >= CDate(Date.Now.ToShortDateString) Then
            'All good new hire scenario
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("NewHire WorkerID Found: {0} - Processed New Hire .",$CCC_Workday_EmployeeID$)))
        Else If ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L" ) _
            AndAlso $EntryDate:Date$ >= CDate(Date.Now.ToShortDateString) _
            AndAlso $CCC_Rehire:Bool$ _
            AndAlso String.IsNullOrEmpty($CCC_LatestWorkerWID$) Then
            'All good Re hire scenario
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("ReHire WorkerID Found: {0} - Processed ReHire .",$CCC_Workday_EmployeeID$)))
        Else If  ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L" ) _
            AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
            AndAlso ($CCC_Conversion_Date:Date$ >= CDate(Date.Now.ToShortDateString) Or $CCC_LatestWorkerWID$=$CCC_WorkdayID$) _
            AndAlso $CCC_Rehire:Bool$ _
            AndAlso $CCC_WorkdayID$ = $CCC_WorkdayID[o]$ _
            AndAlso (Not $IsInActive:Bool$) _
            AndAlso $[IsLoaded]:Bool$ Then
            'All good - rehire of a previously converted user with matching wwid.
            'This Is the situation taking updated From future End point For a precisouly converted account For which wwid switch already happed either In main End point End point sync Or future End point syn.
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Previously Converted ReHire WorkerID Found: {0} - Processed Previously converted ReHire with matching wwid .",$CCC_Workday_EmployeeID$)))
        Else If  ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L" ) _
            AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
            AndAlso ($CCC_Conversion_Date:Date$ >= CDate(Date.Now.ToShortDateString) Or $CCC_LatestWorkerWID$=$CCC_WorkdayID$) _
            AndAlso $CCC_Rehire:Bool$ _
            AndAlso (Not $IsInActive:Bool$) _
            AndAlso (Not $[IsLoaded]:Bool$) Then
            'All good - rehire of a previously converted user. This is a new insert scenario. wwid will be switched at below duplicate account checks. Allowing it to pass through this specific scenario here.
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Previously Converted ReHire WorkerID Found: {0} - Processed Previously converted ReHire, activating the account now .",$CCC_Workday_EmployeeID$)))
        Else
            'vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Validation of Worker from Future Endpoint passed: WorkerID: {0} - Person updated .",$CCC_Workday_EmployeeID$)))
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Skipped From Future Hire EndPoint:MAY NOT BE AN ONBOARDING ACTIVITY: WorkerID Found: {0} - Person not updated .",$CCC_Workday_EmployeeID$)))
            Throw New ViException(String.Format("MAY NOT BE AN ONBOARDING ACTIVITY:Skipping record in Future End Point: {0} -Skipped From Future Hire EndPoint:MAY NOT BE AN ONBOARDING ACTIVITY - object was not saved to Person table.",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)
        End If

    End If
    'Future Validation End

    'Main Validation Start
    If endpointType.Equals(mainEndpoint) Then
        vid_write2log(logFile, String.Format("2-insideMainEndpoint: endpoint: {0} - Sourceendpoint: {1} - workdayWID: {2} - workdayID: {3} - uidPerson: {4} ",endpointType,$CCC_SourceEndpoint$,$CCC_WorkdayID$,$CCC_Workday_EmployeeID$,$UID_Person$))

        Dim isInvalidActiveAccountUpdate As Boolean= $[IsLoaded]:Bool$ AndAlso 'It's an existing identity
                                                     ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L") AndAlso ' Active
                                                     $EntryDate:Date$ < CDate("02/02/1902") 'StartDate is empty


        Dim isInvalidContractor As Boolean= $EmployeeType$="Visitor" AndAlso
                                            (String.IsNullOrEmpty($CCC_Personal_Email$) Or $CCC_Personal_Email$.ToUpper()="WORKDAY_DEFAULT") AndAlso
                                            (String.IsNullOrEmpty($CCC_AlternateEmail$) Or $CCC_AlternateEmail$.ToUpper()="WORKDAY_DEFAULT") AndAlso
                                            Not $CCC_Email_Required:Bool$ AndAlso
                                            (Not String.IsNullOrEmpty($CCC_Workday_Status$) AndAlso ($CCC_Workday_Status$.ToUpper()="A" Or $CCC_Workday_Status$.ToUpper()="L")) AndAlso
                                            $EntryDate:Date$ >= CDate(Date.Now.ToShortDateString)

        Dim isRehireBeforeStartDate As Boolean = $CCC_Rehire[o]:Bool$ AndAlso 'It's a condition to detect rehire - in this case, all the data should come from Future Endpoint and it is not a conversion scenario
                                                 $EntryDate[o]:Date$ > DateTime.Today AndAlso
                                                 Not $CCC_New_Hire_Rescind:Bool$ AndAlso
                                                 Not ($CCC_Workday_Status$ = "A" Or $CCC_Workday_Status$.ToUpper() = "L") AndAlso
                                                 String.IsNullOrEmpty($CCC_LatestWorkerWID$)


        If(isRehireBeforeStartDate) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Skipping rehire account from Main end point since the EntryDate is still in the future. We should grab information from future end point."))
            Throw New ViException(#LD("Worker Import Validation failed: Skipping rehire account from Main end point since the EntryDate is still in the future. We should grab information from future end point.")#, ExceptionRelevance.EndUser)
        End If

        If(isInvalidActiveAccountUpdate) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Invalid ActiveAccountUpdate - Start date for existing active account received empty"))
            Throw New ViException(#LD("Worker Import Validation failed: Invalid ActiveAccountUpdate")#, ExceptionRelevance.EndUser)
        End If

        If(isInvalidContractor) Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Invalid Contractor data - Contractor received with no personal email and alternate email. At least one personal email is required when contractor does not get fhlbc email. Please reach out to HR to capture the email."))
            'Throw New ViException(#LD("Worker Import Validation failed: Invalid Contractor data")#, ExceptionRelevance.EndUser)
        End If

        'skipping an inactive rehire record from main end point.
        If $CCC_Rehire:Bool$ AndAlso $CCC_New_Hire_Date:Date$ > CDate(Date.Now.ToShortDateString) AndAlso $CCC_Workday_Status$.ToUpper() = "I" Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,"Worker Import Validation failed: Skipping inactive rehire account from Main end point. We should grab information from future end point."))
            Throw New ViException(#LD("Skipping account from Main end point: Skipping inactive rehire account from Main end point. We should grab information from future end point.")#, ExceptionRelevance.EndUser)
        End If

    End If
    'Main Validation End
    'Validation End

    'Duplicate handler Start
    Dim colImport As IEntityCollection
    Dim query As Query = Query.From("Person").SelectNone()

    query = query.Select("CCC_WorkdayID")
    query = query.Select("CCC_Workday_EmployeeID")
    query = query.Select("IsInActive")
    query = query.Where(String.Format("isnull(CCC_Workday_EmployeeID,'') = '{0}' And CCC_IsMasterIdentity=1 And (CCC_WorkdayID is null Or CCC_WorkdayID <> '{1}')",$CCC_Workday_EmployeeID$,$CCC_WorkdayID$)).GetQuery()

    colImport = Session.Source().GetCollection(query, EntityCollectionLoadType.Slim)

    If(colImport.Count > 0) Then 'verify if this object is a duplicate

        vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - IsInactive {5} - duplicate wwid {6} ",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,CBool(colImport.Item(0).GetRaw("IsInActive").ToString()),colImport.Item(0).GetRaw("CCC_WorkdayID").ToString()))

        'VID_Write2Log(logFile, $"{timestamp} - {DPR_WrapObjectForProjection(Entity)}")

        'Do not take updates if OIM has multiple accounts found.
        If colImport.Count > 1 Then
            vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,String.Format("Multiple Duplicate accounts Found in OIM: {0} - Analyze why same workday id is assigned to multiple accounts. Fix the accounts in OIM. object was not saved to Person table",$CCC_Workday_EmployeeID$)))
            Throw New ViException(String.Format("Multiple Duplicate accounts Found in OIM: {0} - object was not saved to Person table",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)
        End If
        Dim accIsInActiveCurrently As Boolean = CBool(colImport.Item(0).GetRaw("IsInActive").ToString())
        Dim accWWID As String = colImport.Item(0).GetRaw("CCC_WorkdayID").ToString()
        If endpointType.Equals(mainEndpoint) Then
            vid_write2log(logFile, String.Format("3-insideMainEndpoint: endpoint: {0} - Sourceendpoint: {1} - workdayWID: {2} - workdayID: {3} - uidPerson: {4} ",endpointType,$CCC_SourceEndpoint$,$CCC_WorkdayID$,$CCC_Workday_EmployeeID$,$UID_Person$))

            'Of the two duplicate records only the one that does not match with the wwid in OIM comes up to here
            'Active same day conversion. Switching wwid.
            Dim newHireDate As Date = $CCC_New_Hire_Date:Date$
            If $CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L" _
                AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
                AndAlso CDate(newHireDate.ToShortDateString) = CDate(Date.Now.ToShortDateString) _
                AndAlso (Not CBool(colImport.Item(0).GetRaw("IsInActive").ToString())) _
                AndAlso $CCC_Rehire:Bool$ _
                AndAlso (Not $CCC_Conversion_Rescind:Bool$) Then
                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this is an active same day conversion. Before WWID is updated with the rehired record. Information will be updated in next sync.",$CCC_Workday_EmployeeID$)))

                Dim per2 = Session.Source.Get("Person",colImport.Item(0).GetRaw("UID_Person").ToString(),EntityLoadType.Default)
                Using uow2 = Session.StartUnitOfWork()

                Try
                    per2.PutValue("CCC_WorkdayID",$CCC_WorkdayID$)
                    per2.PutValue("CCC_SourceEndpoint","WIDSWITCH")
                    uow2.Put(per2)
                    uow2.Commit()
                Catch ex As Exception
                    vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5} - {6}",timestamp,$CCC_WorkdayID$,"ERROR",per2.GetValue("CCC_WorkdayID").ToString,$CCC_Workday_EmployeeID$,endpointType,String.Format("Exception occurred when saving {0} : End :",ex.ToString)))
                End Try
                End Using

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5} - {6}",timestamp,$CCC_WorkdayID$,"INFO",per2.GetValue("CCC_WorkdayID").ToString,$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this is an active same day conversion. After WWID is updated with the rehired record. Information will be updated in next sync.",$CCC_Workday_EmployeeID$)))
                Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - INFORMATION ONLY: Preventing new account from getting created. this is an active same day conversion. WWID is updated. Information will be updated in next sync. WID is switched. ",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)

            Else If $CCC_Workday_Status$.ToUpper() = "I" _
                AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
                AndAlso $CCC_New_Hire_Date:Date$ >= CDate(Date.Now.ToShortDateString) _
                AndAlso CBool(colImport.Item(0).GetRaw("IsInActive").ToString()) _
                AndAlso $CCC_Rehire:Bool$ _
                AndAlso (Not $CCC_Conversion_Rescind:Bool$) Then
                'AndAlso colImport.Item(0).GetRaw("CCC_WorkdayID") = $CCC_LatestWorkerWID$ - MO: another condition proposal - might be useful

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this person is getting rehired who had prior conversion. Before WWID is updated with the rehired record. Information will be updated in next sync.",$CCC_Workday_EmployeeID$)))

                Dim per = Session.Source.Get("Person",colImport.Item(0).GetRaw("UID_Person").ToString(),EntityLoadType.Default)
                Using uow = Session.StartUnitOfWork()

                Try
                    per.PutValue("CCC_WorkdayID",$CCC_WorkdayID$)
                    per.PutValue("CCC_SourceEndpoint","WIDSWITCH")
                    uow.Put(per)
                    uow.Commit()
                Catch ex As Exception
                    vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5} - {6}",timestamp,$CCC_WorkdayID$,"ERROR",per.GetValue("CCC_WorkdayID").ToString,$CCC_Workday_EmployeeID$,endpointType,String.Format("Exception occurred when saving {0} : End :",ex.ToString)))
                End Try
                End Using

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5} - {6}",timestamp,$CCC_WorkdayID$,"INFO",per.GetValue("CCC_WorkdayID").ToString,$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this person is getting rehired who had prior conversion. After WWID is updated with the rehired record. Information will be updated in next sync.",$CCC_Workday_EmployeeID$)))
                Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - INFORMATION ONLY: Preventing new account from getting created. This person is getting rehired who had prior conversion. WWID is updated with the rehired record. Information will be updated in next sync. WID is switched. ",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)

            Else If $CCC_Workday_Status$.ToUpper() = "I" _
                AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
                AndAlso $CCC_New_Hire_Date:Date$ <= CDate(Date.Now.ToShortDateString) Then

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} -- {1} - Skipping the inactive account - object was not saved to Person table.",$CCC_Workday_EmployeeID$,endpointType)))
                Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - {1} - Skipping the inactive account - object was not saved to Person table.",$CCC_Workday_EmployeeID$,endpointType), ExceptionRelevance.EndUser)
            Else

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this person is NOT going through a conversion, so a duplicate is NOT expected - object was not saved to Person table",$CCC_Workday_EmployeeID$)))
                Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - this person is NOT going through a conversion, so a duplicate is NOT expected - object was not saved to Person table",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)

            End If
        Else If endpointType.Equals(futureEndpoint) Then
            vid_write2log(logFile, String.Format("4-insideFUTUREEndpoint: endpoint: {0} - Sourceendpoint: {1} - workdayWID: {2} - workdayID: {3} - uidPerson: {4} ",endpointType,$CCC_SourceEndpoint$,$CCC_WorkdayID$,$CCC_Workday_EmployeeID$,$UID_Person$))
            If  ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L" ) _
                AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
                AndAlso ($CCC_Conversion_Date:Date$ >= CDate(Date.Now.ToShortDateString) Or $CCC_LatestWorkerWID$=$CCC_WorkdayID$) _
                AndAlso $CCC_Rehire:Bool$ _
                AndAlso (Not $IsInActive:Bool$) _
                AndAlso accIsInActiveCurrently _
                AndAlso (Not $[IsLoaded]:Bool$) Then
                'All good - rehire of a previously converted user. Switch wwid. so that next sync will pick up the changes.
                Dim per1 = Session.Source.Get("Person",colImport.Item(0).GetRaw("UID_Person").ToString(),EntityLoadType.Default)
                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5} -{6}",timestamp,$CCC_WorkdayID$,"INFO",per1.GetValue("CCC_WorkdayID").ToString,$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this person is getting rehired who had prior conversion. Before WWID is updated to latestwwid with the rehired record . Information will be updated in next sync.",$CCC_Workday_EmployeeID$)))


                Using uow1 = Session.StartUnitOfWork()
                Try
                    per1.PutValue("CCC_WorkdayID",$CCC_WorkdayID$)
                    per1.PutValue("CCC_SourceEndpoint","WIDSWITCH")
                    uow1.Put(per1)
                    uow1.Commit()
                Catch ex As Exception
                    vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5} - {6}",timestamp,$CCC_WorkdayID$,"ERROR",per1.GetValue("CCC_WorkdayID").ToString,$CCC_Workday_EmployeeID$,endpointType,String.Format("Exception occurred when saving {0} : End :",ex.ToString)))

                End Try
                End Using

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Previously Converted ReHire WorkerID Found: {0} - Processed Previously converted ReHire, Switched wwid to latest wwid.",$CCC_Workday_EmployeeID$)))
                Throw New ViException(String.Format("wwid Changed to Latestwwid: Skipping record : {0} - planning to do wwid switch - object was not saved to Person table",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)
            'Skipping active record that shows up in the future end point for future conversions. The record that comes up here is the record that did not have the matching wwid.
            Else If ($CCC_Workday_Status$.ToUpper() = "A" Or $CCC_Workday_Status$.ToUpper() = "L") _
                AndAlso (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
                AndAlso (Not String.IsNullOrEmpty($CCC_Conversion_Type$)) AndAlso $CCC_Conversion_Type$<>"WORKDAY_DEFAULT" _
                AndAlso $CCC_Conversion_Date:Date$ >= CDate(Date.Now.ToShortDateString) Then

                vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this person is going through a conversion, so a duplicate is expected - object was not saved to Person table",$CCC_Workday_EmployeeID$)))
                Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - this person is going through a conversion, so a duplicate is expected - object was not saved to Person table",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)

            'Else
            '   vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"ERROR",$CCC_Workday_EmployeeID$,endpointType,String.Format("Duplicate WorkerID Found: {0} - this person is NOT going through a conversion, so a duplicate is NOT expected - object was not saved to Person table",$CCC_Workday_EmployeeID$)))
            '   Throw New ViException(String.Format("Duplicate WorkerID Found: {0} - this person is NOT going through a conversion, so a duplicate is NOT expected - object was not saved to Person table",$CCC_Workday_EmployeeID$), ExceptionRelevance.EndUser)
            End If
        End If
    End If
    'Once the wwid switch happens in the next workflows it comes back with different UID.
    'Irrespective of any situation prevent any new inserts for conversions
    If colImport.Count=0 _
        And (Not String.IsNullOrEmpty($CCC_LatestWorkerWID$)) _
        And (Not $[IsLoaded]:Bool$) Then
        vid_write2log(logFile, String.Format("{0} - {1} - {2} - {3} - {4} - {5}",timestamp,$CCC_WorkdayID$,"INFO",$CCC_Workday_EmployeeID$,endpointType,String.Format("Previously Converted ReHire WorkerID Found: {0} - Processed Previously converted ReHire, preventing duplicate account creation.",$CCC_Workday_EmployeeID$)))
        Throw New ViException(#LD("Skipping account insert for Conversions: We should never need to insert an account that is going through conversion.")#, ExceptionRelevance.EndUser)
    End If
    'if we reached this place, it means this is not a duplicate - insert
    'Duplicate handler End.
End If
