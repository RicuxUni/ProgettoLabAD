# Relazione di Progetto: Infrastruttura Active Directory e Mail Server 
**(Approccio "Infrastructure as Code" tramite Docker)**

## 1. Contesto e Approccio Metodologico

Il progetto universitario prevede la realizzazione di un'infrastruttura di dominio Active Directory (Samba) per una piccola organizzazione composta da 5 client (computer), 10 utenti interattivi e 10 caselle di posta elettronica da 5 GB (totale 50 GB di storage dedicato alla posta).

Per soddisfare questi requisiti in modo scalabile e riproducibile, l'intero progetto è stato affrontato con una logica **"Infrastructure as Code" (IaC)** fortemente orientata all'utilizzo di **Docker**. Piuttosto che eseguire decine di comandi manuali all'interno della macchina server, **la logica di configurazione è stata codificata all'interno di script, Dockerfile e file di configurazione Compose**. 

Questo approccio permette di definire, avviare e distruggere l'intera infrastruttura (Domain Controller, Web UI, Mail Server e Webmail) con un solo comando, riducendo drasticamente il margine di errore umano.

![Screenshot 1: Architettura di base o Portainer](immagini/img1_architettura.png)

---

## 2. Installazione VM e Preparazione Host (How-To)

In questa fase, è stata preparata la macchina virtuale host che ospiterà i container. Il sistema operativo scelto è **XUbuntu** perché più leggero rispetto ad altre distribuzioni.
![macchina virtuale](immagini/vm.png)

### 2.1 Creazione VM e Partizionamento
La macchina virtuale è stata configurata con un disco da 100 GB. Durante l'installazione del sistema operativo, è stato scelto un partizionamento manuale in base alle esigenze di storage del progetto.
Dato il massiccio utilizzo di container e la necessità di dedicare 50 GB per le e-mail, lo schema di partizionamento applicato è il seguente:
- **`/` (Root)**: 40 GB
- **`/var/lib/docker`**: 60 GB (Questo volume separato garantisce che i dati dei container e le caselle di posta non saturino mai la partizione di sistema).


![Screenshot 2: Schema Partizionamento LVM](immagini/partizionamento.png)

### 2.2 Configurazione di Rete e Risoluzione Conflitti DNS
Samba AD richiede l'uso esclusivo della porta 53 per il proprio server DNS. Su Ubuntu, questa porta è solitamente occupata dal servizio `systemd-resolved`.
È stato quindi necessario disabilitare il listener stub:

```bash
# Modifica del file di configurazione
sudo nano /etc/systemd/resolved.conf 
# Sostituire "#DNSStubListener=yes" con "DNSStubListener=no"

# Riavvio del servizio per applicare la modifica
sudo systemctl restart systemd-resolved

# Ripristino del file resolv.conf per usare un DNS esterno
sudo rm /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

![Modifica a resolved.conf](immagini/resolved.png)
### 2.3 Configurazione del Firewall (UFW)
Per consentire il traffico verso Active Directory e il Mail Server, sono state aperte le porte necessarie nel firewall dell'host:

```bash
sudo ufw allow 53
sudo ufw allow 88
sudo ufw allow 135
sudo ufw allow 137:139/tcp
sudo ufw allow 137:139/udp
sudo ufw allow 389
sudo ufw allow 445
sudo ufw allow 464
sudo ufw allow 636
sudo ufw allow 3268
sudo ufw allow 3269
sudo ufw allow ssh
sudo ufw enable

```


![Screenshot 3: Regole Firewall UFW](immagini/img3_ufw.png)

### 2.4 Installazione di Docker e Portainer
Successivamente, si è proceduto all'installazione di Docker utilizzando il repository ufficiale di Ubuntu:

```bash
# Aggiornamento pacchetti base
sudo apt update && sudo apt upgrade -y

# Aggiunta della chiave GPG ufficiale di Docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Aggiunta del repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installazione dei pacchetti Docker
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verifica installazione
sudo docker run hello-world
```

![hello-world di docker](immagini/docker_hello.png)

Inoltre, per avere un'interfaccia grafica di gestione dei container, è stato installato **Portainer**:
```bash
sudo docker volume create portainer_data
sudo docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
```

![Screenshot 4: Portainer Dashboard](immagini/img4_portainer.png)

### 2.5 Deploy dell'Infrastruttura e Gestione
Una volta preparato l'Host, l'infrastruttura si avvia con i seguenti comandi:
```bash
# Avvio di tutti i container definiti nel Compose
sudo docker compose up -d --build

# Esempio di creazione utente direttamente all'interno del container AD
sudo docker exec -it lalilulelo_ad samba-tool user create <nomeutente> <password>
```
**Tutto il resto dell'installazione è stato delegato ai file sottostanti.**

---

## 3. L'Automazione: Script e File di Configurazione

In questa sezione sono riportati e spiegati i file che costituiscono il core dell'automazione.

### 3.1 Il File Immagine: `Dockerfile`

Pur essendo disponibili delle immagini Samba AD ufficiali, abbiamo deciso di non utilizzare una di quelle per poter capire meglio i vari passaggi della configurazione.

Per gli altri container invece abbiamo utilizzato le immagini ufficiali poiché essi riguardano aspetti marginali del progetto, come la webmail, phpldapadmin e il mailserver. Questi sono stati inclusi per mostrare come Samba possa integrarsi con altri sistemi. Lo stesso per portainer, installato per aver un'interfaccia grafica per la gestione dei container accessibile dal browser del pc fisico.

Il Dockerfile è il seguente:

```dockerfile
FROM ubuntu:24.04

#Evita che durante l'installazione si aprano finestre
ENV DEBIAN_FRONTEND=noninteractive

#aggiorniamo la repository e installiamo Samba, Kerberos e le dipendenze per l'AD DC
#(Active Directory Domain Controller)
RUN apt-get update && apt-get install -y \
    samba \
    smbclient \
    krb5-user \
    winbind \
    libpam-winbind \
    libnss-winbind \
    acl \
    attr \
    dnsutils \
    dos2unix \
    iproute2 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

#copiamo lo script di entrypoint che farà il provisioning dell'AD
COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

#Espone le porte standard di Active Directory
#53(DNS), 88(Kerberos), 135(RPC), 389/636(LDAP/S), 445(SMB)
EXPOSE 53 53/udp 88 88/udp 135 389 389/udp 445 464 464/udp 636

ENTRYPOINT ["/entrypoint.sh"]
```
**Perché in questo modo?** Invece di eseguire `apt install samba` a mano sul server, il container scarica l'OS, installa i pacchetti senza iterazioni utente (`noninteractive`) e inserisce all'interno lo script che lo comanderà.

### 3.2 Il Provisioning Automatico: `entrypoint.sh`
Questo script bash viene lanciato in automatico appena il container nasce. Il suo scopo è creare il Dominio senza che l'utente debba interagire con i comandi di `samba-tool`.

```bash
#!/bin/bash
set -e

#variabili d'ambiente
REALM="${REALM:-LALILULELO.LOCAL}"
DOMAIN="${DOMAIN:-LALILULELO}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-datemi30!}"

#workaround per sovrascrivere il DNS nel container anche in "network_mode: host"
# Dato che hai CAP_SYS_ADMIN, possiamo smontare il file resolv.conf bind-mountato da Docker (o dall'host)
umount /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "search ${REALM}" >> /etc/resolv.conf
echo "=== File /etc/resolv.conf forzato su 127.0.0.1 ==="

# Controlla se l'AD è già stato configurato in passato
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    echo "=== Configurazione iniziale di Samba Active Directory DC ==="

    # Rimuove la configurazione Samba di default che bloccherebbe il provisioning
    rm -f /etc/samba/smb.conf

    # Esegue il provisioning ufficiale dell'Active Directory
    # Usa il DNS interno di Samba per semplicità didattica
    samba-tool domain provision \
        --use-rfc2307 \
        --realm="${REALM}" \
        --domain="${DOMAIN}" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --host-name=ad-dc \
        --option="dns forwarder = 8.8.8.8" \
        --adminpass="${ADMIN_PASSWORD}"

    echo "=== Provisioning completato con successo ==="
else
    echo "=== Active Directory già configurato. Avvio in corso... ==="
fi

# Sovrascrive la configurazione di Kerberos per forzare la risoluzione in locale (su 127.0.0.1)
# bypassando il DNS di Docker che non conosce il nostro dominio
cat <<EOF > /etc/krb5.conf
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = false

[realms]
${REALM} = {
    kdc = 127.0.0.1
}
EOF

# Avvia Samba in modalità "Active Directory Domain Controller" in primo piano (foreground)
# In questo modo il container Docker rimane attivo e mostra i log
exec samba -F

```
**Perché in questo modo?** 
1) Garantisce l'idempotenza: se il dominio esiste già, non lo distrugge, altrimenti crea il reame `LALILULELO.LOCAL`.
2) Risolve un problema noto dell'esecuzione in `network_mode: host`. Se lasciato intatto, il container erediterebbe il DNS dell'host, impedendo al comando `domain provision` di rintracciare se stesso. Con la capability `SYS_ADMIN` dichiarata nel compose, lo script **scollega** (umount) forzatamente il file DNS dell'host per fargli puntare al localhost.

### 3.3 L'Orchestrazione: `docker-compose.yml` 
Il file YAML lega insieme Dominio, Interfaccia grafica (phpldapadmin) e Server di posta (docker-mailserver).

```yaml
services:
  samba-dc:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: lalilulelo_ad
    network_mode: "host" #serve per esporre le porte in automatico, altrimenti sarebbe stato troppo complicato la canfigurazione. In questo modo viene usata la porta di rete e l'indirizzo della macchina host.
    cap_add:
      - SYS_ADMIN
    environment:
      - REALM=LALILULELO.LOCAL
      - DOMAIN=LALILULELO
      - ADMIN_PASSWORD=datemi30!
    dns:
      - 127.0.0.1
    dns_search:
      - LALILULELO.LOCAL
    volumes:
      # Volumi nominali per salvare i dati di Active Directory e la configurazione
      - samba-etc:/etc/samba
      - samba-var:/var/lib/samba
    restart: unless-stopped
  ldap-ui:
    image: osixia/phpldapadmin:latest
    container_name: samba-ad-webui
    ports:
      - "8080:80"
    environment:
      # Modificato in ldaps:// per soddisfare il requisito "strong authentication"
      - PHPLDAPADMIN_LDAP_HOSTS=ldaps://192.168.1.201 #indirizzo della macchina host
      - PHPLDAPADMIN_HTTPS=false
      - PHPLDAPADMIN_LDAP_CLIENT_TLS=true
      - PHPLDAPADMIN_LDAP_CLIENT_TLS_REQCERT=never
    restart: unless-stopped

  mailserver:
    #docker/mailserver è stato rinominato in mailserver/docker-mailserver
    image: mailserver/docker-mailserver:latest
    container_name: mailserver
    hostname: mail.lalilulelo.local
    domainname: lalilulelo.local
    ports:
      - "25:25"
      - "143:143"
      - "587:587"
      - "993:993"
    volumes:
      - maildata:/var/mail
      - mailstate:/var/mail-state
      - maillogs:/var/log/mail
      - ./config:/tmp/docker-mailserver
      - ./user-patches.sh:/tmp/docker-mailserver/user-patches.sh:ro
      - ./ldap.conf:/etc/ldap/ldap.conf:ro
      - ./dovecot-ldap.conf.ext:/etc/dovecot/dovecot-ldap.conf.ext:ro
      - ./dovecot-ldap-tls.conf:/etc/dovecot/conf.d/99-ldap-tls.conf:ro
      - samba-var:/ad-data:ro
    extra_hosts:
      - "ad-dc.lalilulelo.local:192.168.1.201"
    environment:
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_CLAMAV=1
      - ENABLE_FAIL2BAN=0
      - ENABLE_POSTGREY=0
      #La configurazione di LDAP per Active Directory
      - ACCOUNT_PROVISIONER=LDAP
      - LDAP_SERVER_HOST=ldaps://ad-dc.lalilulelo.local:636
      - LDAP_SEARCH_BASE=CN=Users,DC=lalilulelo,DC=local
      - LDAP_BIND_DN=Administrator@lalilulelo.local
      - LDAP_BIND_PW=datemi30!
      - LDAP_QUERY_FILTER_USER=(sAMAccountName=%u)
      - LDAP_QUERY_FILTER_GROUP=(member=%s)
      - LDAP_QUERY_FILTER_ALIAS=(proxyAddresses=smtp:%s)
      - "DOVECOT_PASS_FILTER=(sAMAccountName=%{user | username})"
      - "DOVECOT_USER_FILTER=(sAMAccountName=%{user | username})"
      - DOVECOT_PASS_ATTRS=userPrincipalName=user
      - DOVECOT_USER_ATTRS==uid=5000,=gid=5000
      - DOVECOT_AUTH_BIND=yes
    restart: unless-stopped

  roundcube:
    image: roundcube/roundcubemail:latest
    container_name: roundcube
    ports:
      - "8081:80"
    environment:
      - ROUNDCUBEMAIL_DEFAULT_HOST=mailserver #qua viene usata la rete interna di docker
      - ROUNDCUBEMAIL_SMTP_SERVER=mailserver
    depends_on:
      - mailserver
    restart: unless-stopped

volumes:
  samba-etc:
  samba-var:
  maildata:
  mailstate:
  maillogs:

```
**Analisi:** Nel container del server di posta viene usato il volume `samba.ver` in modo che possa leggere il certificato radice ca.pem generato da samba e possa parlarsi in modalità cifrata
Le variabili LDAP permetto di usare le utenze di Active Directory per autenticarsi al server di posta.

> *📸 **[SEGNAPOSTO SCREENSHOT 6]**: Inserire qui l'output di `docker compose ps` oppure una vista da Portainer che mostra i container "samba-dc" e "mailserver" nello stato "Up/Running".*
![Screenshot 6: Container in esecuzione](immagini/img6_container_up.png)

### 3.4 Autenticazione centralizzata: `dovecot-ldap.conf.ext`
File caricato nel Mail Server come volume, indica a Dovecot come verificare le credenziali che gli arrivano al momento del login.
```ini
hosts = ldaps://ad-dc.lalilulelo.local:636
ldap_version = 3
auth_bind = yes
auth_bind_userdn = %u
dn = Administrator@lalilulelo.local
dnpass = datemi30!
base = DC=LALILULELO,DC=LOCAL
pass_filter = (sAMAccountName=%n)
user_filter = (sAMAccountName=%n)
tls = no
tls_ca_cert_file = /ad-data/private/tls/ca.pem
tls_require_cert = demand
```
**Analisi:** Questa configurazione evita la duplicazione degli account (gli utenti sono creati solo su Samba). Dovecot cerca la corrispondenza del login (es. `enrico`) controllando l'attributo nativo di Windows/Samba `sAMAccountName` (vedi filtri) stabilendo l'autenticità solo se possiede una connessione LDAPS affidabile con Samba (`tls_require_cert = demand`).

> *📸 **[SEGNAPOSTO SCREENSHOT 7]**: Inserire qui un log di sistema del mailserver (`docker logs mailserver`) che mostra una riga di "auth" andata a buon fine per un utente AD, oppure la schermata di login di una webmail/client.*
![Screenshot 7: Test autenticazione LDAP su Mailserver](immagini/img7_ldap_auth.png)

## 4. Conclusione
Tramite la containerizzazione e i file dichiarativi, si è convertito un deployment potenzialmente caotico di centinaia di comandi in un ecosistema auto-sufficiente che, di base, parte semplicemente digitando `docker compose up -d`. L'intera topologia è "documentata dal codice stesso", in conformità con i migliori paradigmi DevOps.

> *📸 **[SEGNAPOSTO SCREENSHOT 8]**: (Opzionale ma d'impatto) Inserire qui uno screenshot di un client Windows (es. Windows 10/11) correttamente unito al dominio `LALILULELO.LOCAL`, oppure dell'interfaccia RSAT che mostra gli utenti caricati sul server.*
![Screenshot 8: Risultato Finale - Client a dominio](immagini/img8_risultato_finale.png)
