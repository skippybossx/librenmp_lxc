#!/bin/bash

# Funkcja do znalezienia pierwszego wolnego CTID
get_next_ctid() {
    local ctid=100
    while pct status $ctid &>/dev/null; do
        ctid=$((ctid + 1))
    done
    echo $ctid
}

# Zmienne
CTID=$(get_next_ctid)
HOSTNAME="librenms"
PASSWORD="librenms"
TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
BRIDGE="vmbr0"

# Wykrywanie dostępnego storage obsługującego szablony
STORAGE=$(pvesm status -content vztmpl | awk 'NR==2{print $1}')
if [ -z "$STORAGE" ]; then
    echo "Brak dostępnego storage obsługującego szablony. Sprawdź konfigurację Proxmoxa."
    exit 1
fi

# Pobieranie szablonu Debian 12, jeśli nie jest dostępny
if ! pveam list $STORAGE | grep -q $TEMPLATE; then
    pveam update
    pveam download $STORAGE $TEMPLATE
fi

# Tworzenie i uruchamianie kontenera LXC
pct create $CTID $STORAGE:vztmpl/$TEMPLATE --hostname $HOSTNAME --password $PASSWORD --net0 name=eth0,bridge=$BRIDGE,ip=dhcp --start 1

# Oczekiwanie na uzyskanie adresu IP przez kontener
sleep 10

# Pobieranie adresu IP kontenera
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

# Sprawdzanie, czy kontener uzyskał adres IP
if [ -z "$IP" ]; then
    echo "Kontener nie uzyskał adresu IP. Sprawdź konfigurację sieci."
    exit 1
fi

# Definiowanie URL-i plików do pobrania
FILES=(
  "https://raw.githubusercontent.com/skippybossx/librenmp_lxc/main/ct/librenms.sh"
  "https://raw.githubusercontent.com/skippybossx/librenmp_lxc/main/install/librenms-install.sh"
  "https://raw.githubusercontent.com/skippybossx/librenmp_lxc/main/json/librenms.json"
)

# Definiowanie docelowych katalogów w kontenerze
DIRECTORIES=(
  "/ct"
  "/install"
  "/json"
)

# Tworzenie katalogów i pobieranie plików
for i in "${!FILES[@]}"; do
  pct exec $CTID -- mkdir -p "${DIRECTORIES[$i]}"
  pct exec $CTID -- wget -O "${DIRECTORIES[$i]}/$(basename ${FILES[$i]})" "${FILES[$i]}"
done

# Nadawanie uprawnień wykonywania dla skryptu instalacyjnego
pct exec $CTID -- chmod +x /cp/librenms.sh

# Uruchamianie skryptu instalacyjnego
pct exec $CTID -- /cp/librenms.sh

# Wyświetlanie wyniku
echo "LibreNMS został pomyślnie zainstalowany i jest dostępny pod adresem http://$IP"
