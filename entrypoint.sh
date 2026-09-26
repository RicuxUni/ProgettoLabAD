#!/bin/bash
set -e

# Variabili d'ambiente di default (sovrascrivibili al run)
REALM="${REALM:-LALILULELO.LOCAL}"
DOMAIN="${DOMAIN:-LALILULELO}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-datemi30!}"

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
