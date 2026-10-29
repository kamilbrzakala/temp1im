New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Force | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name AuthServerAllowlist -Value 'fhcwbidmmp14,*.fhlbc.loc' -PropertyType String -Force
