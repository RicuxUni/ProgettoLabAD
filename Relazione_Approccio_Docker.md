# Relazione di Progetto: Infrastruttura Active Directory e Mail Server 
**(Approccio "Infrastructure as Code" tramite Docker)**

## 1. Contesto e Approccio Metodologico

Il progetto universitario prevede la realizzazione di un'infrastruttura di dominio Active Directory (Samba) per una piccola organizzazione composta da 5 client (computer), 10 utenti interattivi e 10 caselle di posta elettronica da 5 GB (totale 50 GB di storage dedicato alla posta).

Per soddisfare questi requisiti in modo scalabile e riproducibile, l'intero progetto è stato affrontato con una logica **"Infrastructure as Code" (IaC)** fortemente orientata all'utilizzo di **Docker**. Piuttosto che eseguire decine di comandi manuali all'interno della macchina server, **la logica di configurazione è stata codificata all'interno di script, Dockerfile e file di configurazione Compose**. 

Questo approccio permette di definire, avviare e distruggere l'intera infrastruttura (Domain Controller, Web UI, Mail Server e Webmail) con un solo comando, riducendo drasticamente il margine di errore umano.

---

## 2. Preparazione: Le uniche operazioni eseguite a mano (Host)

La macchina virtuale ospitante è una Ubuntu Server con 100 GB di disco partizionati tramite LVM. Dato il massiccio utilizzo di container e la necessità di 50 GB per le e-mail, al volume `/var/lib/docker` sono stati assegnati 60 GB, salvaguardando così la partizione Root.

Le uniche operazioni svolte interattivamente (a riga di comando) sull'Host sono state quelle preparatorie:
1. **Risoluzione conflitti DNS**: 
   Samba AD richiede la porta 53, solitamente occupata dal sistema operativo. È stato necessario disabilitare a mano `systemd-resolved`:
   ```bash
   sudo nano /etc/systemd/resolved.conf # Modificato DNSStubListener=no
   sudo systemctl restart systemd-resolved
   sudo rm /etc/resolv.conf && sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
   ```
2. **Configurazione UFW (Firewall)**: 
   Sono state aperte manualmente le porte del dominio (`ufw allow 53, 88, 135, 137, 139, 389, 445, 464, 636, 3268, 3269`).
3. **Installazione Engine Docker**:
   Scarico repository e installazione standard di Docker CE e Docker Compose.
4. **Deploy e Gestione Quotidiana**:
   - Avvio: `docker compose up -d --build`
   - Creazione utenti via Samba: `docker exec -it lalilulelo_ad samba-tool user create enrico Password123!`

**Tutto il resto dell'installazione è stato delegato ai file sottostanti.**

---

## 3. L'Automazione: Script e File di Configurazione

In questa sezione sono riportati e spiegati i file che costituiscono il core dell'automazione.

### 3.1 Il File Immagine: `Dockerfile`
Non essendoci un'immagine Samba AD ufficiale adatta alle nostre esigenze, ne è stata costruita una partendo da Ubuntu nudo.

```dockerfile
FROM ubuntu:24.04

# Evita che durante l'installazione si aprano finestre
ENV DEBIAN_FRONTEND=noninteractive

# Aggiorniamo le repository e installiamo Samba, Kerberos e le dipendenze
RUN apt-get update && apt-get install -y \
    samba smbclient krb5-user winbind libpam-winbind libnss-winbind \
    acl attr dnsutils dos2unix iproute2 iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Copiamo lo script di entrypoint che farà il provisioning dell'AD
COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

# Espone le porte standard di Active Directory
EXPOSE 53 53/udp 88 88/udp 135 389 389/udp 445 464 464/udp 636

ENTRYPOINT ["/entrypoint.sh"]
```
**Perché in questo modo?** Invece di eseguire `apt install samba` a mano sul server, il container scarica l'OS, installa i pacchetti senza iterazioni utente (`noninteractive`) e inserisce all'interno lo script che lo comanderà.

### 3.2 Il Provisioning Automatico: `entrypoint.sh`
Questo script bash viene lanciato in automatico appena il container nasce. Il suo scopo è creare il Dominio senza che l'utente debba interagire con i comandi di `samba-tool`.

```bash
#!/bin/bash
set -e

# Variabili d'ambiente ereditate dal Compose
REALM="${REALM:-LALILULELO.LOCAL}"
DOMAIN="${DOMAIN:-LALILULELO}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-datemi30!}"

# Workaround per sovrascrivere il DNS nel container anche in "network_mode: host"
# Richiede CAP_SYS_ADMIN. Smontiamo il resolv.conf bind-mountato da Docker (o dall'host)
umount /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "search ${REALM}" >> /etc/resolv.conf
echo "=== File /etc/resolv.conf forzato su 127.0.0.1 ==="

# Controlla se l'AD è già stato configurato in passato
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    echo "=== Configurazione iniziale di Samba Active Directory DC ==="
    rm -f /etc/samba/smb.conf

    # Esegue il provisioning ufficiale in automatico
    samba-tool domain provision \
        --use-rfc2307 \
        --realm="${REALM}" \
        --domain="${DOMAIN}" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --host-name=ad-dc \
        --option="dns forwarder = 8.8.8.8" \
        --adminpass="${ADMIN_PASSWORD}"
else
    echo "=== Active Directory già configurato. Avvio in corso... ==="
fi

# Sovrascrive Kerberos per risolvere il ticket localmente
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

# Avvia il demone
exec samba -F
```
**Perché in questo modo?** 
1) Garantisce l'idempotenza: se il dominio esiste già, non lo distrugge, altrimenti crea il reame `LALILULELO.LOCAL`.
2) Risolve un problema noto dell'esecuzione in `network_mode: host`. Se lasciato intatto, il container erediterebbe il DNS dell'host, impedendo al comando `domain provision` di rintracciare se stesso. Con la capability `SYS_ADMIN` dichiarata nel compose, lo script **scollega** (umount) forzatamente il file DNS dell'host per fargli puntare al localhost.

### 3.3 L'Orchestrazione: `docker-compose.yml` (Estratto)
Il file YAML lega insieme Dominio, Interfaccia grafica (phpldapadmin) e Server di posta (docker-mailserver).

```yaml
services:
  samba-dc:
    build: .
    container_name: lalilulelo_ad
    network_mode: "host"
    cap_add:
      - SYS_ADMIN
    environment:
      - REALM=LALILULELO.LOCAL
      - DOMAIN=LALILULELO
      - ADMIN_PASSWORD=datemi30!
    volumes:
      - samba-etc:/etc/samba
      - samba-var:/var/lib/samba

  mailserver:
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
      - ./dovecot-ldap.conf.ext:/etc/dovecot/dovecot-ldap.conf.ext:ro
      - samba-var:/ad-data:ro
    environment:
      - ACCOUNT_PROVISIONER=LDAP
      - LDAP_SERVER_HOST=ldaps://ad-dc.lalilulelo.local:636
      - LDAP_BIND_DN=Administrator@lalilulelo.local
      - LDAP_BIND_PW=datemi30!
      - LDAP_SEARCH_BASE=CN=Users,DC=lalilulelo,DC=local
      - LDAP_QUERY_FILTER_USER=(sAMAccountName=%u)
```
**Analisi:** L'utilizzo dei Volumi Docker (`samba-var`) permette di passare, in sola lettura (`:ro`), il file autorizzativo `ca.pem` (Certificato radice generato da Samba) direttamente al server Mail, affinché i due sistemi possano parlarsi in modalità cifrata (LDAPS). Le variabili LDAP sostituiscono l'onere di configurare un client di posta utente per utente.

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

## 4. Conclusione
Tramite la containerizzazione e i file dichiarativi, si è convertito un deployment potenzialmente caotico di centinaia di comandi in un ecosistema auto-sufficiente che, di base, parte semplicemente digitando `docker compose up -d`. L'intera topologia è "documentata dal codice stesso", in conformità con i migliori paradigmi DevOps.
