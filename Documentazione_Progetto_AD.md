# Documentazione Progetto: Active Directory con Samba, Mail Server e Client Linux

## 1. Introduzione
Il presente documento illustra i passaggi eseguiti per la realizzazione di un'infrastruttura di dominio basata su **Active Directory (AD)** utilizzando **Samba** su container Docker. Il progetto include la configurazione dell'host, il provisioning del dominio, l'integrazione di un server di posta elettronica autenticato via LDAP, e il join di un client Linux al dominio.

## 2. Preparazione dell'Host (Ubuntu)
Per garantire il corretto funzionamento del container Samba AD in modalità host, sono stati effettuati i seguenti interventi sul sistema ospitante:
- **Installazione Docker**: Sono stati aggiunti i repository ufficiali e installati i pacchetti `docker-ce` e i relativi plugin, oltre a **Portainer** per la gestione visiva dei container.
- **Configurazione di Rete e DNS**: È stato disabilitato il servizio `systemd-resolved` per liberare la porta 53, necessaria al DNS interno di Samba. Il file `/etc/resolv.conf` è stato ricreato per far puntare il sistema al DNS corretto, evitando conflitti di risoluzione.
- **Configurazione Firewall (UFW)**: Sono state aperte le porte necessarie al funzionamento di Active Directory:
  - DNS: `53` (TCP/UDP)
  - Kerberos: `88`, `464` (TCP/UDP)
  - RPC: `135` (TCP)
  - NetBIOS / SMB: `137-139` (TCP/UDP), `445` (TCP)
  - LDAP / LDAPS: `389`, `636`, `3268`, `3269` (TCP)

## 3. Creazione del Domain Controller (Samba AD)
Il Domain Controller è stato containerizzato tramite un setup Docker personalizzato:
- **Configurazione Container**: Nel `docker-compose.yml`, il servizio `samba-dc` è stato configurato con `network_mode: "host"` e la capability `SYS_ADMIN`.
- **Provisioning Automatico**: Lo script `entrypoint.sh` si occupa del provisioning del dominio (`LALILULELO.LOCAL`) tramite il comando `samba-tool domain provision`. È stato scelto il backend `SAMBA_INTERNAL` per il DNS.
- **Workaround DNS locale**: L'`entrypoint.sh` sovrascrive il file `/etc/resolv.conf` e `/etc/krb5.conf` all'interno del container per forzare la risoluzione sul localhost (`127.0.0.1`), bypassando le configurazioni dell'host o di Docker.
- **Interfaccia Web**: È stato integrato il container `phpldapadmin` per poter esplorare e gestire l'albero LDAP graficamente, configurato per connettersi al DC tramite protocollo LDAPS sicuro.

## 4. Integrazione del Server di Posta
Il servizio di posta elettronica è stato implementato tramite `docker-mailserver`, affiancato da `Roundcube` come webmail. 
Il server di posta è stato collegato all'Active Directory in modo da centralizzare l'autenticazione degli account utente:
- **Connessione Sicura LDAP (LDAPS)**: Il mail server interroga il Domain Controller sulla porta `636`. Per permettere a `Dovecot` (il demone IMAP) di fidarsi della connessione, il certificato della CA generato automaticamente da Samba (`ca.pem`) è stato condiviso col mail server tramite il volume Docker `samba-var`.
- **Configurazione LDAP**: Nel file `docker-compose.yml`, le variabili d'ambiente del mailserver sono state impostate per usare l'AD come backend:
  - `ACCOUNT_PROVISIONER=LDAP`
  - `LDAP_SERVER_HOST=ldaps://ad-dc.lalilulelo.local:636`
  - `LDAP_BIND_DN=Administrator@lalilulelo.local`
- **Mappatura Utenti (Dovecot)**: Attraverso i file di configurazione (`dovecot-ldap.conf.ext`), l'autenticazione è stata istruita a cercare l'utente tramite l'attributo `sAMAccountName` (il nome utente di login di Windows). Se le credenziali coincidono su AD, il mail server garantisce l'accesso alla casella di posta.

## 5. Join di un Client Linux (Xubuntu) al Dominio
A dimostrazione del funzionamento del dominio, un client Xubuntu esterno è stato unito ad esso:
- **Impostazione DNS**: La scheda di rete del client è stata configurata tramite `NetworkManager` (`nmcli`) per usare l'IP del Domain Controller (`192.168.1.201`) come DNS primario.
- **Autenticazione**: Tramite i pacchetti `realmd`, `sssd` e `krb5-user` è stata verificata l'infrastruttura (con `kinit` per i ticket Kerberos).
- **Join e Accesso**: Con `sudo realm join lalilulelo.local -U enrico` la macchina è entrata nel dominio. Modificando il sistema PAM (`pam_oddjob_mkhomedir.so`) è stata abilitata la creazione automatica delle home directory al primo accesso degli utenti di dominio (eseguito con successo anche tramite SSH).

---

## 6. Vademecum: Principali Comandi in Esercizio

Di seguito un riepilogo dei comandi utili per l'amministrazione quotidiana del laboratorio.

### Gestione Infrastruttura Docker
- **Avviare i servizi (in background)**:
  ```bash
  docker compose up -d --build
  ```
- **Visualizzare i log di Samba in tempo reale**:
  ```bash
  docker logs -f lalilulelo_ad
  ```

### Gestione Utenti e Gruppi in Active Directory
Questi comandi utilizzano l'utilità `samba-tool` e devono essere inviati al container del Domain Controller tramite `docker exec`.

- **Creare un nuovo utente**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user create nome_utente Password123!
  ```
- **Elencare tutti gli utenti del dominio**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user list
  ```
- **Aggiungere un utente a un gruppo (es. Domain Admins)**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool group addmembers "Domain Admins" nome_utente
  ```
- **Elencare i gruppi del dominio**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool group list
  ```
- **Reimpostare la password di un utente**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user setpassword nome_utente --newpassword=NuovaPassword123!
  ```
- **Disabilitare / Abilitare un utente**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user disable nome_utente
  docker exec -it lalilulelo_ad samba-tool user enable nome_utente
  ```

### Test e Verifica
Comandi utili da eseguire direttamente sulla macchina Host o su un client:
- **Ottenere un ticket Kerberos per un utente**:
  ```bash
  kinit nome_utente@LALILULELO.LOCAL
  ```
- **Visualizzare i ticket Kerberos correnti**:
  ```bash
  klist
  ```
- **Verificare l'accesso a una condivisione SMB/Samba**:
  ```bash
  smbclient -L localhost -U "nome_utente%Password123!"
  ```
- **Verificare l'identità passata da AD (su un client Linux in dominio)**:
  ```bash
  id nome_utente@lalilulelo.local
  ```
