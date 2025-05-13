#!/bin/bash

# Update and upgrade packages
echo "Updating package list..."
sudo apt-get update -y
echo "Upgrading installed packages..."
sudo apt-get upgrade -y

# Install WireGuard
echo "Installing WireGuard..."
sudo apt-get install -y wireguard

# Install Azure CLI for Key Vault access
echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Generate WireGuard keys
echo "Generating WireGuard keys..."
wg genkey | sudo tee /etc/wireguard/privatekey | sudo chmod 600 /etc/wireguard/privatekey
sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey

# Get Key Vault info
VM_NAME=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)

# Try to get the server public key from Key Vault
SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'serverpublickey' --query value -o tsv 2>/dev/null || echo "")

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.10.0.2/24
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = $(cat /etc/wireguard/serverpublickey 2>/dev/null || echo "PLACEHOLDER")
Endpoint = <PUBLICIP_or_DNS>:51820
AllowedIPs = 192.168.1.0/24
PersistentKeepalive = 25
EOF"

# Set permissions
sudo chmod 600 /etc/wireguard/wg0.conf

# Store the public key in Azure Key Vault
VM_PUBLIC_KEY=$(cat /etc/wireguard/publickey)
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name 'WGVMPublicKey' --value "$VM_PUBLIC_KEY"

# Enable and start WireGuard
echo "Enabling and starting WireGuard service..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Check if WireGuard tunnel is up
echo "Checking WireGuard tunnel status..."
sleep 5
if sudo wg show wg0 > /dev/null 2>&1; then
    echo "WireGuard tunnel wg0 is up and running."
    sudo wg show wg0
else
    echo "WireGuard tunnel wg0 failed to start. Check configuration and logs."
    sudo systemctl status wg-quick@wg0 --no-pager
fi

# Create a cron job to check for the serverpublickey and update the config, only restart the service if key changes
CRON_SCRIPT="/usr/local/bin/update-wg-serverkey.sh"
sudo bash -c "cat > $CRON_SCRIPT << 'EOS'
#!/bin/bash
KEYVAULT_NAME=\"$KEYVAULT_NAME\"
SERVER_PUBLIC_KEY=\$(az keyvault secret show --vault-name \"\$KEYVAULT_NAME\" --name 'serverpublickey' --query value -o tsv 2>/dev/null || echo \"\")
if [[ -n "$SERVER_PUBLIC_KEY" ]]; then
    CURRENT_KEY_FILE="/etc/wireguard/serverpublickey"
    if [[ ! -f "$CURRENT_KEY_FILE" ]] || [[ "$SERVER_PUBLIC_KEY" != "$(cat $CURRENT_KEY_FILE)" ]]; then
        echo "$SERVER_PUBLIC_KEY" | sudo tee "$CURRENT_KEY_FILE" > /dev/null
        sudo systemctl restart wg-quick@wg0
    fi
fi
EOS"
sudo chmod +x $CRON_SCRIPT
# Add cron job to run every 15 minutes
( sudo crontab -l 2>/dev/null; echo "*/15 * * * * $CRON_SCRIPT" ) | sudo crontab -

echo "WireGuard installation and setup complete."