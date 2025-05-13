#!/bin/bash

# Update and upgrade packages
echo "Updating package list..."
sudo apt-get update -y
echo "Upgrading installed packages..."
sudo apt-get upgrade -y

# Install WireGuard
echo "Installing WireGuard..."
sudo apt-get install -y wireguard

# Generate WireGuard keys
echo "Generating WireGuard keys..."
wg genkey | sudo tee /etc/wireguard/privatekey | sudo chmod 600 /etc/wireguard/privatekey
sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
sudo bash -c 'cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.10.0.2/24  # Azure VM WireGuard IP (use a unique subnet for WG tunnel)
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = <ServerPublicKey>  # Your home router's WireGuard public key
Endpoint = <PUBLICIP_or_DNS>:51820  # Your home router's public IP or DNS name
AllowedIPs = 192.168.1.0/24  # Your home LAN subnet
PersistentKeepalive = 25
EOF'

# Set permissions
sudo chmod 600 /etc/wireguard/wg0.conf

# Enable and start WireGuard
echo "Enabling and starting WireGuard service..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

echo "WireGuard installation and setup complete."


# Check if WireGuard tunnel is up
echo "Checking WireGuard tunnel status..."
sleep 5  # Wait a few seconds for the tunnel to establish
if sudo wg show wg0 > /dev/null 2>&1; then
    echo "WireGuard tunnel wg0 is up and running."
    sudo wg show wg0
else
    echo "WireGuard tunnel wg0 failed to start. Check configuration and logs."
    sudo systemctl status wg-quick@wg0 --no-pager
fi

echo "WireGuard installation and setup complete."

