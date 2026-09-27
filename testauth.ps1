Add-Type -AssemblyName System.DirectoryServices.Protocols

$serverIp = "192.168.1.201" #impostato sulla vodafone station in dhcp reservations
$username = "enrico@LALILULELO.LOCAL" 
$password = "Password123!"

try {
    Write-Host "Tentativo di connessione LDAP puro a $serverIp..."
    
    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($serverIp, 389)
    $credential = New-Object System.Net.NetworkCredential($username, $password)
    
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection($identifier, $credential)
    $connection.SessionOptions.ProtocolVersion = 3
    $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Ntlm
    
    # Il metodo Bind() effettua l'effettiva validazione delle credenziali sul server LDAP
    $connection.Bind()
    
    Write-Host ">>> AUTENTICAZIONE LDAP RIUSCITA CON SUCCESSO DA WINDOWS! <<<" -ForegroundColor Green
    
    # Chiusura connessione
    $connection.Dispose()
} catch {
    Write-Host ">>> AUTENTICAZIONE FALLITA: $($_.Exception.Message) <<<" -ForegroundColor Red
}
