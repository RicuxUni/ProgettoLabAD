#!/bin/bash
#
# join-ad-domain.sh
#
# Script per il join di un client Ubuntu/Xubuntu a un dominio Active Directory
# tramite realmd/sssd, con configurazione DNS permanente via NetworkManager
# e verifica finale del login.
#
# Uso:
#   sudo ./join-ad-domain.sh
#
# Lo script chiede in modo interattivo i parametri necessari (dominio, IP del
# DC, utente per il join) e non richiede modifiche al codice.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Verifica prerequisiti
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Questo script deve essere eseguito con sudo/root." >&2
    exit 1
fi

echo "=== Join al dominio Active Directory ==="
echo

read -rp "Nome del dominio (es. lalilulelo.local): " DOMAIN
read -rp "IP del Domain Controller / DNS server (es. 192.168.1.201): " DC_IP
read -rp "Nome dell'interfaccia di rete (verifica con 'ip link show', es. enp0s3): " IFACE
read -rp "Utente AD con permessi di join (es. enrico): " JOIN_USER

REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

echo
echo "Riepilogo:"
echo "  Dominio:       $DOMAIN"
echo "  Realm:         $REALM"
echo "  DC/DNS:        $DC_IP"
echo "  Interfaccia:   $IFACE"
echo "  Utente join:   $JOIN_USER"
read -rp "Confermi? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Annullato."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Installazione pacchetti necessari
# ---------------------------------------------------------------------------

echo
echo ">>> [1/7] Installazione pacchetti..."

apt update
apt install -y \
    openssh-server \
    realmd sssd sssd-tools libnss-sss libpam-sss adcli \
    samba-common-bin oddjob oddjob-mkhomedir packagekit \
    krb5-user

systemctl enable --now ssh

# ---------------------------------------------------------------------------
# 2. Configurazione DNS permanente tramite NetworkManager
# ---------------------------------------------------------------------------

echo
echo ">>> [2/7] Configurazione DNS permanente (NetworkManager)..."

CONN_NAME=$(nmcli -t -f NAME,DEVICE con show | grep ":${IFACE}$" | cut -d: -f1)

if [[ -z "$CONN_NAME" ]]; then
    echo "Impossibile trovare una connessione NetworkManager per l'interfaccia '$IFACE'." >&2
    echo "Controlla l'output di 'nmcli con show' e rilancia lo script." >&2
    exit 1
fi

echo "Connessione NetworkManager trovata: $CONN_NAME"

nmcli con mod "$CONN_NAME" ipv4.dns "$DC_IP"
nmcli con mod "$CONN_NAME" ipv4.dns-search "$DOMAIN"
nmcli con mod "$CONN_NAME" ipv4.ignore-auto-dns yes
nmcli con up "$CONN_NAME"

echo "Stato DNS attuale:"
resolvectl status "$IFACE" || resolvectl status

# ---------------------------------------------------------------------------
# 3. Verifica risoluzione DNS del dominio (record SRV)
# ---------------------------------------------------------------------------

echo
echo ">>> [3/7] Verifica risoluzione DNS del dominio..."

if ! nslookup -type=SRV "_ldap._tcp.${DOMAIN}" > /tmp/srv_check.log 2>&1; then
    echo "ATTENZIONE: impossibile risolvere i record SRV di ${DOMAIN}." >&2
    cat /tmp/srv_check.log >&2
    echo "Verifica manualmente prima di proseguire (DNS/DC raggiungibile?)." >&2
    read -rp "Vuoi continuare comunque? [y/N] " CONT
    [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
else
    echo "Record SRV LDAP trovati correttamente:"
    cat /tmp/srv_check.log
fi

# ---------------------------------------------------------------------------
# 4. Test isolato di autenticazione Kerberos
# ---------------------------------------------------------------------------

echo
echo ">>> [4/7] Test Kerberos (kinit) per l'utente '$JOIN_USER'..."
echo "Verrà richiesta la password dell'utente."

if kinit "${JOIN_USER}@${REALM}"; then
    echo "kinit riuscito, ticket ottenuto:"
    klist
    kdestroy
else
    echo "kinit fallito: verifica credenziali, orologio di sistema e DNS prima di proseguire." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 5. Discovery e join al dominio
# ---------------------------------------------------------------------------

echo
echo ">>> [5/7] Discovery del dominio..."
realm discover "$DOMAIN"

echo
echo ">>> Join al dominio (verrà richiesta di nuovo la password)..."
realm join "$DOMAIN" -U "$JOIN_USER"

echo
echo "Stato del join:"
realm list

# ---------------------------------------------------------------------------
# 6. Configurazione creazione automatica home directory
# ---------------------------------------------------------------------------

echo
echo ">>> [6/7] Configurazione creazione automatica home directory..."

PAM_FILE="/etc/pam.d/common-session"
PAM_LINE="session optional pam_oddjob_mkhomedir.so umask=0077"

if ! grep -qF "pam_oddjob_mkhomedir.so" "$PAM_FILE"; then
    sed -i "/pam_unix.so/a ${PAM_LINE}" "$PAM_FILE"
    echo "Riga aggiunta a $PAM_FILE"
else
    echo "pam_oddjob_mkhomedir.so già presente in $PAM_FILE, nessuna modifica necessaria."
fi

systemctl restart sssd

# ---------------------------------------------------------------------------
# 7. Verifica finale
# ---------------------------------------------------------------------------

echo
echo ">>> [7/7] Verifica finale identità utente..."
echo "Esegui manualmente per completare la verifica:"
echo
echo "    id ${JOIN_USER}@${DOMAIN}"
echo "    getent passwd ${JOIN_USER}@${DOMAIN}"
echo "    su - ${JOIN_USER}@${DOMAIN}"
echo
echo "=== Join al dominio completato con successo ==="
