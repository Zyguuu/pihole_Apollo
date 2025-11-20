#!/bin/bash

# Skrypt konfiguracji Linux Server - Samba AD DC + DHCP + Shares
# OpenSUSE Leap 16.0
# Autor: Generated from exam documentation

set -e

# Zmienne konfiguracyjne - DOSTOSUJ PRZED UŻYCIEM!
STATION_NUMBER="01"
DOMAIN_NAME="nazwisko-klasa.local"
SERVER_NAME="Server-AD"
INTERNAL_INTERFACE="eth0"  # Sprawdź właściwą nazwę
NAT_INTERFACE="eth1"       # Sprawdź właściwą nazwę
LINUX_CLIENT_MAC="00:11:22:33:44:55"  # Wprowadź właściwy MAC
WINDOWS_SERVER_MAC="66:77:88:99:AA:BB" # Wprowadź właściwy MAC

echo "=== Rozpoczynanie konfiguracji Linux Server ==="

# 1. Konfiguracja adresu IP dla sieci wewnętrznej
echo "1. Konfiguracja IP sieci wewnętrznej..."
INTERNAL_IP="192.168.250.${STATION_NUMBER}/24"
nmcli con mod "$INTERNAL_INTERFACE" ipv4.addresses "$INTERNAL_IP" ipv4.method manual
nmcli con down "$INTERNAL_INTERFACE"
nmcli con up "$INTERNAL_INTERFACE"

# 2. Konfiguracja IP dla NAT (automatycznie)
echo "2. Konfiguracja IP NAT (automatycznie)..."
nmcli con mod "$NAT_INTERFACE" ipv4.method auto
nmcli con down "$NAT_INTERFACE" 
nmcli con up "$NAT_INTERFACE"

# 3. Instalacja oprogramowania
echo "3. Instalacja pakietów..."
zypper refresh
zypper in -y -f samba-ad-dc krb5-server dhcp-server

# 4. Ustawienie nazwy hosta
echo "4. Konfiguracja nazwy hosta..."
hostnamectl set-hostname "$SERVER_NAME"
echo "127.0.0.1 $SERVER_NAME $DOMAIN_NAME ${SERVER_NAME}.${DOMAIN_NAME}" >> /etc/hosts

# 5. Promocja do kontrolera domeny
echo "5. Konfiguracja kontrolera domeny Samba AD..."
rm -f /etc/samba/smb.conf

# Automatyczna odpowiedź na polecenie provision
samba-tool domain provision \
    --realm="${DOMAIN_NAME^^}" \
    --domain="${DOMAIN_NAME%%.*}" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="ZAQ!2wsx" \
    --use-rfc2307 \
    --function-level=2008_R2

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

systemctl enable --now samba-ad-dc
systemctl disable --now firewalld

# 6. Konfiguracja serwera DHCP
echo "6. Konfiguracja serwera DHCP..."
cp /etc/dhcpd.conf /etc/dhcpd.conf.back

cat > /etc/dhcpd.conf << EOF
subnet 192.168.250.0 netmask 255.255.255.0 {
    range 192.168.250.240 192.168.250.250;
    option domain-name-servers 192.168.250.${STATION_NUMBER};
    option domain-name "${DOMAIN_NAME}";
    default-lease-time 600;
    
    host linux-client {
        hardware ethernet ${LINUX_CLIENT_MAC};
        fixed-address 192.168.250.100;
    }
    
    host windows-server {
        hardware ethernet ${WINDOWS_SERVER_MAC};
        fixed-address 192.168.250.200;
    }
}
EOF

echo "DHCPD_INTERFACE=\"$INTERNAL_INTERFACE\"" > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd

# 7. Konfiguracja SELinux
echo "7. Konfiguracja SELinux..."
semanage fcontext -a -t samba_share_t "/srv/samba(/.*)?"
restorecon -Rv /srv/samba
setsebool -P samba_domain_controller on
setsebool -P samba_export_all_rw on

# 8. Udostępnianie folderu wspólnego
echo "8. Tworzenie i udostępnianie folderów..."
mkdir -p /srv/samba/wspolny
mkdir -p /srv/samba/profile
mkdir -p /srv/samba/dane

chmod 777 /srv/samba/wspolny
chmod 777 /srv/samba/profile  
chmod 777 /srv/samba/dane

# Dodawanie udziałów do smb.conf
cat >> /etc/samba/smb.conf << EOF

[zadania]
path = /srv/samba/wspolny
guest ok = no
browseable = yes
read only = no
create mask = 0777
directory mask = 0777

[profile]
path = /srv/samba/profile
guest ok = no
browseable = yes
read only = no
create mask = 0777
directory mask = 0777

[dane]
path = /srv/samba/dane
guest ok = no
browseable = yes
read only = no
create mask = 0777
directory mask = 0777
EOF

# Restart usługi Samba
systemctl restart samba-ad-dc

# 9. Tworzenie użytkownika domeny
echo "9. Tworzenie użytkownika domeny..."
samba-tool user create a.nowak 'ZAQ12wsx' \
    --must-change-at-next-login=no \
    --password-never-expires \
    --profile-path="\\\\${SERVER_NAME}.${DOMAIN_NAME}\\profile\\a.nowak" \
    --home-drive='Z:' \
    --home-directory="\\\\${SERVER_NAME}.${DOMAIN_NAME}\\dane\\a.nowak"

# 10. Konfiguracja stref DNS
echo "10. Dodawanie strefy DNS..."
samba-tool dns zonecreate localhost bogobo.com -U administrator --password=ZAQ!2wsx
samba-tool dns add localhost bogobo.com @ A 123.123.123.123 -U administrator --password=ZAQ!2wsx

echo "=== Konfiguracja zakończona pomyślnie! ==="
echo "Serwer: $SERVER_NAME"
echo "Domena: $DOMAIN_NAME" 
echo "IP: 192.168.250.$STATION_NUMBER"
echo "Hasło administratora: ZAQ!2wsx"
