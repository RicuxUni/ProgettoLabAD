## Join di un client Linux (Xubuntu) al dominio e verifica dell'autenticazione

A completamento del progetto, è stato verificato che il Domain Controller sia in grado di autenticare correttamente un client Linux esterno, distinto dalle macchine Docker utilizzate per la creazione del dominio. A tale scopo è stata utilizzata una VM Xubuntu 26.04 LTS, unita al dominio `lalilulelo.local` (realm `LALILULELO.LOCAL`) tramite lo stack `realmd`/`sssd`, e sono stati eseguiti test di login reali con un utente di dominio (`enrico`).

### Preparazione ambiente e accesso remoto

Per operare più comodamente, è stato abilitato l'accesso SSH alla VM:

```sh
sudo apt update
sudo apt install openssh-server
sudo systemctl start ssh
```

Sono stati quindi installati i pacchetti necessari per l'integrazione con Active Directory:

```sh
sudo apt install realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
```

### Configurazione del DNS verso il Domain Controller

Il client risultava inizialmente configurato con il DNS del router (`192.168.1.1`) e nessun dominio di ricerca impostato, impedendo la risoluzione dei record SRV necessari alla scoperta del DC. La configurazione è stata corretta e resa **permanente** tramite NetworkManager, per evitare che venisse sovrascritta al riavvio o al rinnovo del lease DHCP:

```sh
sudo nmcli con mod "netplan-enp0s3" ipv4.dns "192.168.1.201"
sudo nmcli con mod "netplan-enp0s3" ipv4.dns-search "lalilulelo.local"
sudo nmcli con mod "netplan-enp0s3" ipv4.ignore-auto-dns yes
sudo nmcli con up "netplan-enp0s3"
```

La verifica con `resolvectl status` conferma la configurazione corretta e stabile:

```
DNS Servers: 192.168.1.201
DNS Domain: lalilulelo.local
```

Il corretto funzionamento del DNS del DC è stato inoltre confermato dall'interrogazione dei record SRV di Active Directory:

```
_ldap._tcp.lalilulelo.local  service = 0 100 389 ad-dc.lalilulelo.local
```

### Verifica isolata dell'autenticazione Kerberos

Prima di procedere al join, è stato verificato che il DC rilasci correttamente i ticket Kerberos per l'utente di dominio:

```sh
sudo apt install krb5-user -y
#inserisci LALILULELO.LOCAL come realm

kinit enrico@LALILULELO.LOCAL
klist
```

Il comando ha restituito un Ticket Granting Ticket valido (`krbtgt/LALILULELO.LOCAL@LALILULELO.LOCAL`), a conferma che il servizio Kerberos del DC autentica correttamente le credenziali.

### Discovery e join al dominio

```sh
sudo realm discover lalilulelo.local
sudo realm join lalilulelo.local -U enrico
```

Il comando `realm join` ha configurato automaticamente `sssd` (file `/etc/sssd/sssd.conf`), completando il join senza necessità di configurazione manuale di Samba/Kerberos.

Lo stato del join è stato verificato con:

```sh
realm list
```

che conferma il dominio come correttamente configurato (`configured: kerberos-member`), con `sssd` come client software e `login-policy: allow-realm-logins`.

### Verifica del login e dell'identità utente

Dopo aver abilitato la creazione automatica della home directory (`pam_oddjob_mkhomedir.so` in `/etc/pam.d/common-session`), sono stati effettuati con successo test di login con l'utente di dominio, sia localmente:

```sh
sudo sed -i '/pam_unix.so/a session optional pam_oddjob_mkhomedir.so umask=0077' /etc/pam.d/common-session
su - enrico@lalilulelo.local
```

sia via SSH, sia in locale sulla VM sia da un client Windows remoto sulla stessa rete, confermando l'autenticazione anche in un contesto di accesso realmente distribuito.

Infine, è stata verificata l'identità mappata dal DC per l'utente tramite:

```sh
id enrico@lalilulelo.local
```

con risultato:

```
uid=1222401103(enrico@lalilulelo.local)
gid=1222400513(domain users@lalilulelo.local)
groups=1222400513(domain users@lalilulelo.local),
       1222400512(domain admins@lalilulelo.local),
       1222400572(denied rodc password replication group@lalilulelo.local)
```

Il risultato conferma che il sistema riceve dal DC un'identità completa e coerente con quella definita in Active Directory, inclusa l'appartenenza dell'utente `enrico` al gruppo **Domain Admins**.

### Conclusioni della verifica

I test condotti dimostrano che il Domain Controller opera correttamente anche verso un client Linux esterno all'infrastruttura Docker: pubblica i servizi DNS necessari alla scoperta del dominio, autentica le credenziali via Kerberos, gestisce correttamente il join tramite `realmd`/`sssd`, ed espone identità utente coerenti (UID, GID, appartenenza ai gruppi) utilizzabili per l'autenticazione e l'autorizzazione a livello di sistema operativo.