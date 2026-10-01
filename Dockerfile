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