#!/bin/bash

# Function to find the first available CTID
get_next_ctid() {
    local ctid=100
    while pct status $ctid &>/dev/null; do
        ctid=$((ctid + 1))
    done
    echo $ctid
}

# Variables
CTID=$(get_next_ctid)
HOSTNAME="librenms"
PASSWORD="librenms"
TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
BRIDGE="vmbr0"

# Determine available storage
STORAGE=$(pvesm status -content rootdir | awk 'NR==2{print $1}')

# Download Debian 12 template if not already present
if ! pveam list $STORAGE | grep -q $TEMPLATE; then
    pveam update
    pveam download $STORAGE $TEMPLATE
fi

# Create and start the LXC container
pct create $CTID $STORAGE:vztmpl/$TEMPLATE --hostname $HOSTNAME --password $PASSWORD --net0 name=eth0,bridge=$BRIDGE,ip=dhcp --start 1

# Wait for the container to obtain an IP address
sleep 10

# Get the IP address of the container
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

# Define the URLs of the files to download
FILES=(
  "https://raw.githubusercontent.com/skippybossx/librenmp_lxc/main/ct/librenms.sh"
  "https://raw.githubusercontent.com/skippybossx/librenmp_lxc/main/install/librenms-install.sh"
  "https://raw.githubusercontent.com/skippybossx/librenmp_lxc/main/json/librenms.json"
)

# Define the target directories in the container
DIRECTORIES=(
  "/ct"
  "/install"
  "/json"
)

# Create directories and download files
for i in "${!FILES[@]}"; do
  pct exec $CTID -- mkdir -p "${DIRECTORIES[$i]}"
  pct exec $CTID -- wget -O "${DIRECTORIES[$i]}/$(basename ${FILES[$i]})" "${FILES[$i]}"
done

# Make the install script executable
pct exec $CTID -- chmod +x /install/librenms-install.sh

# Run the install script
pct exec $CTID -- /install/librenms-install.sh

# Output the result
echo "LibreNMS has been successfully installed and is available at http://$IP"
