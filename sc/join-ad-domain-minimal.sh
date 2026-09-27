#!/bin/bash
set -e

# --- Parametri cablati ---
DOMAIN="lalilulelo.local"
REALM="LALILULELO.LOCAL"
DC_IP="192.168.1.201"
IFACE="enp0s3"
JOIN_USER="enrico"

# 1. Pacchetti
apt update
apt install -y openssh-server realmd sssd sssd-tools libnss-sss libpam-sss \
    adcli samba-common-bin oddjob oddjob-mkhomedir packagekit krb5-user
systemctl enable --now ssh

# 2. DNS permanente
CONN_NAME=$(nmcli -t -f NAME,DEVICE con show | grep ":${IFACE}$" | cut -d: -f1)
nmcli con mod "$CONN_NAME" ipv4.dns "$DC_IP"
nmcli con mod "$CONN_NAME" ipv4.dns-search "$DOMAIN"
nmcli con mod "$CONN_NAME" ipv4.ignore-auto-dns yes
nmcli con up "$CONN_NAME"

# 3. Test Kerberos
kinit "${JOIN_USER}@${REALM}"
klist
kdestroy

# 4. Join al dominio
realm discover "$DOMAIN"
realm join "$DOMAIN" -U "$JOIN_USER"
realm list

# 5. Home directory automatica
grep -qF "pam_oddjob_mkhomedir.so" /etc/pam.d/common-session || \
    sed -i '/pam_unix.so/a session optional pam_oddjob_mkhomedir.so umask=0077' /etc/pam.d/common-session
systemctl restart sssd

echo "Join completato. Verifica con: id ${JOIN_USER}@${DOMAIN}"
