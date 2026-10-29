# 1. Create the cert (put every name you will use in the URL into DnsName)
$fqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
$cert = New-SelfSignedCertificate `
    -DnsName $fqdn, $env:COMPUTERNAME, "localhost" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -FriendlyName "OIM Dev HTTPS" `
    -KeyAlgorithm RSA -KeyLength 2048 `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(3)
$cert.Thumbprint

# 2. Trust it on this machine, so browsers and the OIM installer/API Server accept it
$tmp = "$env:TEMP\oim-dev.cer"
Export-Certificate -Cert $cert -FilePath $tmp | Out-Null
Import-Certificate -FilePath $tmp -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null

# 3. Bind it to HTTPS 443 on the Default Web Site
Import-Module WebAdministration
if (-not (Get-WebBinding -Name "Default Web Site" -Protocol https)) {
    New-WebBinding -Name "Default Web Site" -Protocol https -Port 443
}
(Get-WebBinding -Name "Default Web Site" -Protocol https).AddSslCertificate($cert.Thumbprint, "My")
