# Relazione di Progetto: Infrastruttura Active Directory con Samba, Mail Server e Client Join

## 1. Contesto e Obiettivi del Progetto

Il presente progetto universitario ha lo scopo di progettare, implementare e documentare un'infrastruttura di rete basata su **Active Directory (AD)** utilizzando **Samba** in ambiente Linux. Il dominio (chiamato `LALILULELO.LOCAL`) deve fornire servizi di autenticazione e autorizzazione centralizzata.

**Dimensionamento e Requisiti:**
L'infrastruttura è stata pensata per supportare una piccola organizzazione composta da:
- **5 computer** (client) iscritti a dominio.
- **10 utenti interattivi**.
- **10 caselle di posta elettronica**, con una quota prevista di **5 GB** ciascuna (per un totale di 50 GB dedicati esclusivamente allo storage delle email).

Per garantire portabilità e isolamento, l'architettura dei servizi (Domain Controller, Mail Server e Webmail) è basata su **Docker**.

---

## 2. Preparazione della Macchina Virtuale Host

Il server principale che ospita i container è stato installato tramite una macchina virtuale (es. VMware/VirtualBox). Come sistema operativo è stato scelto **Ubuntu Server LTS**, ideale per ospitare engine Docker in produzione.

### 2.1 Schema di Partizionamento

Tenendo conto del dimensionamento richiesto (in particolare i 50 GB necessari per la posta), è stato allocato un disco virtuale di **100 GB** complessivi. In fase di installazione di Ubuntu, è stato scelto un partizionamento manuale basato su **LVM (Logical Volume Manager)** per garantire flessibilità futura:

- **`/boot`** (`ext4`, 1 GB): Partizione per kernel e bootloader.
- **`swap`** (4 GB): Spazio di paginazione.
- **`/` (Root)** (`ext4`, 35 GB): Per il sistema operativo e i pacchetti software.
- **`/var/lib/docker`** (`ext4`, 60 GB): Volume logico dedicato interamente ai container, ai database di Active Directory e ai volumi persistenti delle email (che assorbiranno circa 50 GB a regime). Separare `/var/lib/docker` previene che il riempimento delle caselle postali blocchi il sistema operativo (Saturazione della Root).

*![Screenshot: Schema di partizionamento durante l'installazione di Ubuntu]*

---

## 3. Configurazione Preliminare del Sistema Host (How-To)

Dopo aver completato l'installazione della VM e configurato un IP statico, si è proceduto alla preparazione dell'ambiente.

### 3.1 Risoluzione dei Conflitti DNS (Porta 53)
Active Directory è fortemente dipendente dal DNS (Domain Name System). Samba AD include un proprio server DNS interno che deve essere in ascolto sulla porta `53`. Su Ubuntu, il servizio `systemd-resolved` occupa di default questa porta. È necessario disabilitarlo.

```bash
# Verifica occupazione porta 53
sudo ss -tulpn | grep :53

# Modifica il file per disabilitare il listener
sudo nano /etc/systemd/resolved.conf
```
Sostituire la riga `#DNSStubListener=yes` con `DNSStubListener=no`.

```bash
# Riavvia il servizio e configura un resolver temporaneo
sudo systemctl restart systemd-resolved
sudo rm /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

### 3.2 Configurazione Firewall (UFW)
Per ragioni di sicurezza, è stato abilitato il firewall aprendo unicamente le porte strettamente necessarie al funzionamento dei servizi Active Directory, LDAP, Kerberos e SMB.

```bash
sudo ufw allow 53           # DNS
sudo ufw allow 88           # Kerberos
sudo ufw allow 135          # RPC
sudo ufw allow 137:139/tcp  # SMB / NetBIOS
sudo ufw allow 137:139/udp
sudo ufw allow 389          # LDAP
sudo ufw allow 445          # SMB over TCP
sudo ufw allow 464          # Kerberos Password Change
sudo ufw allow 636          # LDAPS
sudo ufw allow 3268         # Global Catalog
sudo ufw allow 3269         # Global Catalog SSL
sudo ufw enable
```

### 3.3 Installazione Docker
Per ospitare l'infrastruttura, è stato aggiunto il repository ufficiale e installato Docker:

```bash
sudo apt update && sudo apt upgrade -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

*![Screenshot: Verifica installazione Docker con hello-world]*

---

## 4. Implementazione del Domain Controller Samba

Il cuore del progetto è basato su un container Docker personalizzato per avviare il servizio `samba-ad-dc`.

### 4.1 La scelta dell' `entrypoint.sh`
Perché usare uno script di avvio personalizzato anziché eseguire direttamente l'immagine standard?
1. **Provisioning Automatico**: AD richiede che il dominio venga inizializzato al primo avvio. L'entrypoint controlla se il file `sam.ldb` (database LDAP) esiste in `/var/lib/samba/private/`. Se non c'è, avvia in automatico il comando `samba-tool domain provision` con le variabili (`REALM`, `DOMAIN`, `ADMIN_PASSWORD`) passate dal `docker-compose.yml`. Questo rende l'infrastruttura usa-e-getta e facilmente replicabile.
2. **Workaround di Rete in modalità Host**: Poiché Samba deve emulare un server reale a basso livello, è obbligatorio usare `network_mode: "host"` unito alla capability `SYS_ADMIN`. Purtroppo, Docker in modalità host inietta il DNS del SO principale dentro il container. Questo impedisce a Samba di risolvere se stesso durante il provisioning.
L'entrypoint esegue uno **smontaggio di forza** di `/etc/resolv.conf` (possibile grazie a `SYS_ADMIN`) e inietta `127.0.0.1`, permettendo al container di risolvere correttamente il proprio dominio tramite il DNS interno che sta creando. Stessa forzatura viene fatta su `/etc/krb5.conf`.

### 4.2 Avvio dell'Infrastruttura
Il `docker-compose.yml` orchestra tre stack logici: il Domain Controller (`samba-dc`), un Web UI per gestire l'AD (`phpldapadmin`) e il Mail Server.

Per avviare l'infrastruttura:
```bash
# Avvio di tutti i container in background
docker compose up -d --build
```
*![Screenshot: Output del comando docker compose up -d --build con esito positivo]*

---

## 5. Implementazione del Server di Posta (Autenticazione AD)

Per gestire i 10 utenti e le relative caselle da 5 GB, è stato impiegato `docker-mailserver` con l'interfaccia `roundcube`.

### 5.1 Scelte Progettuali: LDAP TLS
La direttiva aziendale/accademica impone che gli account utente non siano replicati localmente sul server di posta, ma interrogati al momento del login al Domain Controller. Questo garantisce gestione centralizzata (SSO).
- **Variabili nel compose**: Al mailserver sono passate variabili cruciali come `ACCOUNT_PROVISIONER=LDAP`, l'host `ldaps://ad-dc.lalilulelo.local:636`, il base DN e i filtri di ricerca basati su `sAMAccountName`.
- **Certificati TLS**: Poiché Windows (e Samba) rifiutano di default bind in chiaro per operazioni sensibili, è stato abilitato **LDAPS (LDAP Over SSL)**. Il mailserver legge il certificato autorizzativo emesso al boot da Samba (condiviso sul volume docker `samba-var`) dichiarandolo nel file `dovecot-ldap.conf.ext` tramite: `tls_ca_cert_file = /ad-data/private/tls/ca.pem`.
In questo modo, Dovecot (il server IMAP/POP3) può interrogare il database di Active Directory su un canale cifrato.

*![Screenshot: Login alla webmail roundcube con le credenziali di dominio]*

---

## 6. Join del Client Linux (Xubuntu) al Dominio

È stata preparata una VM client (Xubuntu) per simulare le 5 macchine aziendali.

### 6.1 Preparazione DNS (NetworkManager)
Affinché il client scopra il Dominio, il DNS del router deve essere rimosso e sostituito dall'IP dell'host Docker. La modifica deve essere persistente tramite NetworkManager:

```bash
sudo nmcli con mod "netplan-enp0s3" ipv4.dns "192.168.1.201"
sudo nmcli con mod "netplan-enp0s3" ipv4.dns-search "lalilulelo.local"
sudo nmcli con mod "netplan-enp0s3" ipv4.ignore-auto-dns yes
sudo nmcli con up "netplan-enp0s3"
```

### 6.2 Verifica Kerberos e Join al Dominio
L'autenticazione è stata verificata tramite pacchetti nativi.

```bash
sudo apt install realmd sssd sssd-tools libnss-sss libpam-sss adcli krb5-user

# Verifica del ticket TGT (il DC autentica correttamente le credenziali)
kinit enrico@LALILULELO.LOCAL
klist
```
*![Screenshot: Output del comando klist che mostra il Ticket Kerberos valido]*

Esecuzione del Join:
```bash
sudo realm discover lalilulelo.local
sudo realm join lalilulelo.local -U Administrator
```
Per permettere la creazione automatica delle home al primo accesso, è stato inserito `pam_oddjob_mkhomedir.so` in `/etc/pam.d/common-session`.

Test finale di accesso:
```bash
# Verifica mappatura utente fornita da AD
id enrico@lalilulelo.local
# uid=1222401103(enrico@lalilulelo.local) gid=1222400513(domain users...)
```
*![Screenshot: Comando 'id' e switch su utente 'enrico' sul terminale Linux client]*

---

## 7. Vademecum: Principali Comandi in Esercizio

Per l'amministrazione dei 10 utenti creati, occorre collegarsi al container del Domain Controller.

### Gestione Utenti e Gruppi in AD (`samba-tool`)
Eseguire dal terminale Host:

- **Creazione Utente**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user create enrico Password123!
  ```
- **Aggiunta utente al gruppo Amministratori**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool group addmembers "Domain Admins" enrico
  ```
- **Reset Password**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user setpassword enrico --newpassword=1234567-A
  ```
- **Elenco e disattivazione utenti**:
  ```bash
  docker exec -it lalilulelo_ad samba-tool user list
  docker exec lalilulelo_ad samba-tool user disable enrico
  ```

### Test Diagnostici
- **Controllare i log di sistema del mailserver**:
  ```bash
  docker logs -f mailserver
  ```
- **Esplorare il server Samba (dal client)**:
  ```bash
  smbclient -L localhost -U "enrico%Password123!"
  ```
