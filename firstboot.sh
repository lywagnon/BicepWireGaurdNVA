#!/bin/bash
SCRIPT_PATH="$(readlink -f "$0")"
# Record the script start time
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
echo "Script started at: $START_TIME"

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

#if script is not running from /home/azureuser/firstboot.sh, wait for 60 seconds to allow managed identity to propagate
if [[ "$SCRIPT_PATH" != "/home/azureuser/firstboot.sh" ]]; then
    # Wait until 60 seconds have passed since script start time to allow managed identity to propagate
    START_EPOCH=$(date -d "$START_TIME" +%s)
    while true; do
        NOW_EPOCH=$(date +%s)
        ELAPSED=$((NOW_EPOCH - START_EPOCH))
        if (( ELAPSED >= 60 )); then
            echo "60 seconds have elapsed since script start. Continuing..."
            break
        else
            REMAINING=$((60 - ELAPSED))
            echo "Waiting for managed identity propagation... $REMAINING seconds remaining."
            sleep 5
        fi
    done
fi

# Login to Azure CLI using user assigned managed identity, tenant, and subscription
echo "Logging in to Azure CLI with user assigned managed identity..."
AZ_LOGIN_OUTPUT=$(az login --identity --allow-no-subscriptions)
if [[ -z "$AZ_LOGIN_OUTPUT" ]]; then
    echo "ERROR: az login did not return any output. Exiting."
    exit 1
fi

# Get Key Vault info
VM_NAME=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)

# Check that required variables are not blank or empty
if [[ -z "$VM_NAME" || -z "$RESOURCE_GROUP" || -z "$KEYVAULT_NAME" ]]; then
    echo "ERROR: One or more required variables (VM_NAME, RESOURCE_GROUP, KEYVAULT_NAME) are empty. Exiting."
    exit 1
else
    echo "VM Name: $VM_NAME"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Key Vault Name: $KEYVAULT_NAME"
    echo "Script Path: $SCRIPT_PATH"  
fi
# # Pause and wait for user to press any key before continuing
# read -n 1 -s -r -p "Press any key to continue..."
# echo

# Try to get the private and public keys from Key Vault
echo "Trying to get the private and public keys from Key Vault..."
VM_PRIVATE_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-privatekey" --query value -o tsv 2>/dev/null || echo "")
VM_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-publickey" --query value -o tsv 2>/dev/null || echo "")

# Output the first 7 characters of both keys for verification
echo "VM_PUBLIC_KEY (first 7 chars): ${VM_PUBLIC_KEY:0:7}"
echo "VM_PRIVATE_KEY (first 7 chars): ${VM_PRIVATE_KEY:0:7}"

# Check to see if the keys were retrieved successfully
if [[ -n "$VM_PRIVATE_KEY" && -n "$VM_PUBLIC_KEY" ]]; then
    echo "Found existing WireGuard keys in Key Vault. Writing to files..."
    echo "$VM_PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey >/dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    echo "$VM_PUBLIC_KEY" | sudo tee /etc/wireguard/publickey >/dev/null
    sudo chmod 600 /etc/wireguard/publickey
else
    echo "Unable to retrieve Secrets from KV"
    echo "Either the keys do not exist in Key Vault or there was an error retrieving them."
    echo "Generating new WireGuard keys..."

    wg genkey | sudo tee /etc/wireguard/privatekey >/dev/null
    sudo chmod 600 /etc/wireguard/privatekey

    sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey >/dev/null
    sudo chmod 600 /etc/wireguard/publickey

    echo "You can overwrite the keys in Key Vault with the new ones if needed."

    # Store the new public key in Azure Key Vault
    VM_PUBLIC_KEY=$(cat /etc/wireguard/publickey)
    if [[ -n "$VM_PUBLIC_KEY" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-publickey" --value "$VM_PUBLIC_KEY" >/dev/null
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Failed to store VM public key in Key Vault."
            exit 1
        fi
        echo "Stored VM public key in Key Vault."
        echo "VM_PUBLIC_KEY: $VM_PUBLIC_KEY"
    fi

    # Store the new private key in Azure Key Vault
    VM_PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
    if [[ -n "$VM_PRIVATE_KEY" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-privatekey" --value "$VM_PRIVATE_KEY" >/dev/null
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Failed to store VM private key in Key Vault."
            exit 1
        fi
        echo "Stored VM private key in Key Vault."
        echo "VM_PRIVATE_KEY: $VM_PRIVATE_KEY"
    fi
fi

# Try to get the server public key from Key Vault
REMOTE_SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to retrieve remoteserverpublickey from Key Vault."
    exit 1
fi

if [[ -n "$REMOTE_SERVER_PUBLIC_KEY" ]]; then
    sudo mkdir -p /etc/wireguard
    echo "$REMOTE_SERVER_PUBLIC_KEY" | sudo tee /etc/wireguard/remoteserverpublickey > /dev/null
    sudo chmod 600 /etc/wireguard/remoteserverpublickey
else
    echo "No remoteserverpublickey found in Key Vault. Please ensure it is set up."
    exit 1
fi

# Try to get the server public key from Key Vault
REMOTE_ROUTER=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoterouter' --query value -o tsv 2>/dev/null || echo "")
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to retrieve remoterouter from Key Vault. IP:PORT or FQDN:PORT"
    exit 1
fi

# Validate REMOTE_ROUTER is in IP:PORT or FQDN:PORT format
if ! [[ "$REMOTE_ROUTER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ || "$REMOTE_ROUTER" =~ ^([a-zA-Z0-9.-]+):[0-9]{1,5}$ ]]; then
    echo "ERROR: remoterouter value '$REMOTE_ROUTER' is not a valid IP:PORT or FQDN:PORT."
    exit 1
fi

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
MTU = 1420
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 192.168.2.7/32 #tunnel interface
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = $(cat /etc/wireguard/remoteserverpublickey 2>/dev/null || echo "PLACEHOLDER")
Endpoint = ${REMOTE_ROUTER:-PLACEHOLDER}
AllowedIPs = 192.168.1.0/24
PersistentKeepalive = 25
EOF"

# Set permissions
sudo chmod 600 /etc/wireguard/wg0.conf

#restart wiregaurd service to apply new keys if it was already running
sudo systemctl restart wg-quick@wg0 

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
    exit 1
fi

if [[ "$SCRIPT_PATH" == "/home/azureuser/firstboot.sh" ]]; then

echo "Setting up cron job and firstboot.sh script to start on VM boot..."

# Download or update update-wg-key.sh in /usr/local/bin only if the remote file has changed

USER_SCRIPT="/home/azureuser/update-wg-key.sh"
CRON_SCRIPT="/usr/local/bin/update-wg-key.sh"
LOCAL_COMMIT_FILE="/usr/local/bin/update-wg-key.sh.commit"

# Get the latest commit SHA for update-wg-key.sh from GitHub
REMOTE_COMMIT=$(curl -fsSL "https://api.github.com/repos/MicrosoftAzureAaron/BicepWireGaurdNVA/commits?path=update-wg-key.sh&sha=main&per_page=1" | grep '"sha":' | head -n 1 | awk -F '"' '{print $4}')

LOCAL_COMMIT=""
if [[ -f "$LOCAL_COMMIT_FILE" ]]; then
    LOCAL_COMMIT=$(cat "$LOCAL_COMMIT_FILE")
fi

if [[ "$REMOTE_COMMIT" != "$LOCAL_COMMIT" && -n "$REMOTE_COMMIT" ]]; then
    echo "[firstboot.sh] New commit detected for update-wg-key.sh, downloading updated script."
    curl -fsSL -o "$USER_SCRIPT" "https://raw.githubusercontent.com/MicrosoftAzureAaron/BicepWireGaurdNVA/main/update-wg-key.sh"
    sudo chown azureuser:azureuser "$USER_SCRIPT"
    sudo chmod +x "$USER_SCRIPT"
    sudo mv "$USER_SCRIPT" "$CRON_SCRIPT"
    sudo chmod +x "$CRON_SCRIPT"
    echo "$REMOTE_COMMIT" | sudo tee "$LOCAL_COMMIT_FILE" >/dev/null
else
    echo "[firstboot.sh] No changes detected for update-wg-key.sh, skipping download."
    # Ensure the script exists and is executable
    if [[ ! -f "$CRON_SCRIPT" ]]; then
        curl -fsSL -o "$CRON_SCRIPT" "https://raw.githubusercontent.com/MicrosoftAzureAaron/BicepWireGaurdNVA/main/update-wg-key.sh"
        sudo chmod +x "$CRON_SCRIPT"
    fi
fi

CRON_TARGET="$CRON_SCRIPT"

# Add cron job to run every 5 minutes, ensuring no duplicates
# Remove any existing cron jobs for this script
sudo crontab -l 2>/dev/null | grep -v "$CRON_TARGET" | sudo crontab -
# Add the new cron job
( sudo crontab -l 2>/dev/null; echo "*/5 * * * * $CRON_TARGET" ) | sudo crontab -

echo "WireGuard installation and setup complete."

# Copy the firstboot.sh script to /home/azureuser/ only if not already running from there
if [[ "$SCRIPT_PATH" != "/home/azureuser/firstboot.sh" ]]; then
    sudo cp /var/lib/waagent/custom-script/download/0/firstboot.sh /home/azureuser/firstboot.sh
    sudo chmod +x /home/azureuser/firstboot.sh
    # Ensure the script is owned by azureuser
    sudo chown azureuser:azureuser /home/azureuser/firstboot.sh
fi

# Ensure firstboot.sh runs at VM startup via systemd service

SERVICE_FILE="/etc/systemd/system/firstboot.service"
sudo bash -c "cat > $SERVICE_FILE << EOF
[Unit]
Description=Run firstboot.sh at startup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=azureuser
ExecStart=/home/azureuser/firstboot.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable firstboot.service

fi
# End of script