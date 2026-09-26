# 1. Partiamo da un'immagine OS ufficiale e pulita
FROM ubuntu:24.04

# 2. Evita che i pacchetti aprano finestre di dialogo interattive durante l'installazione
ENV DEBIAN_FRONTEND=noninteractive

# 3. Aggiorna i repository e installa Samba, Kerberos e le dipendenze per l'AD DC
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
    && rm -rf /var/lib/apt/lists/*

# 4. Copia lo script di entrypoint (lo creeremo al punto 2) che farà il provisioning dell'AD
COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

# 5. Espone le porte standard di Active Directory (opzionale, utile come documentazione)
# 53 (DNS), 88 (Kerberos), 135 (RPC), 389/636 (LDAP/S), 445 (SMB)
EXPOSE 53 53/udp 88 88/udp 135 389 389/udp 445 464 464/udp 636

ENTRYPOINT ["/entrypoint.sh"]