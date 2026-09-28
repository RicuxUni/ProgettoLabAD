#!/bin/bash
# user-patches.sh - eseguito da docker-mailserver all'avvio del container
# Installa il certificato CA di Samba AD nel trust store di sistema
# in modo che Dovecot (e qualsiasi altra libreria) si fidi di LDAPS

echo "user-patches.sh: Installazione CA Samba AD nel trust store di sistema..."

if [ -f /ad-data/private/tls/ca.pem ]; then
    cp /ad-data/private/tls/ca.pem /usr/local/share/ca-certificates/samba-ad-ca.crt
    update-ca-certificates
    echo "user-patches.sh: CA installata con successo."
else
    echo "user-patches.sh: ATTENZIONE - /ad-data/private/tls/ca.pem non trovato!"
fi
