$domain = "LDAP://127.0.0.1"
$username = "LALILULELO\mappopo"
$password = "Qualiano123!"

try {
    # Usiamo DirectoryEntry (ADSI) con autenticazione Sicura (Secure)
    # Questo soddisfa il requisito di crittografia forte di Samba AD DC
    $entry = New-Object System.DirectoryServices.DirectoryEntry($domain, $username, $password, [System.DirectoryServices.AuthenticationTypes]::Secure)
    
    # Forza la connessione effettuando una ricerca
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
    $searcher.Filter = "(sAMAccountName=mappopo)"
    $result = $searcher.FindOne()
    
    if ($result) {
        Write-Host ">>> AUTENTICAZIONE ADSI RIUSCITA CON SUCCESSO DA WINDOWS! <<<" -ForegroundColor Green
    } else {
        Write-Host ">>> AUTENTICAZIONE FALLITA: Utente non trovato. <<<" -ForegroundColor Red
    }
} catch {
    Write-Host ">>> AUTENTICAZIONE FALLITA: $($_.Exception.Message) <<<" -ForegroundColor Red
}
