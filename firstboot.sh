#!/bin/bash
SCRIPT_PATH="$(readlink -f "$0")"

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

# if script is running for the first time, generate keys and store them in Key Vault
if [[ "$SCRIPT_PATH" == "/home/azureuser/firstboot.sh" ]]; then
    echo "Running for the first time. Checking for existing WireGuard keys in Key Vault..."
    if [[ -n "$VM_PRIVATE_KEY" && -n "$VM_PUBLIC_KEY" ]]; then
        echo "Found existing WireGuard keys in Key Vault. Writing to files..."
        echo "$VM_PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey >/dev/null
        sudo chmod 600 /etc/wireguard/privatekey
        echo "$VM_PUBLIC_KEY" | sudo tee /etc/wireguard/publickey >/dev/null
        sudo chmod 600 /etc/wireguard/publickey
    else
        echo "Unable to retrieve Secrets from KV"
        echo "Please ensure the secrets ${VM_NAME}-privatekey and ${VM_NAME}-publickey are set in Key Vault."
        echo "VM_PRIVATE_KEY: $VM_PRIVATE_KEY"
        echo "VM_PUBLIC_KEY: $VM_PUBLIC_KEY"
        exit 1
    fi
else
    # # Generate WireGuard keys
    # read -n 1 -s -r -p "Running for the First Time. Generating WireGuard keys. Press any key to continue..."
    # echo
    echo "Generating new WireGuard keys..."
    wg genkey | sudo tee /etc/wireguard/privatekey >/dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey >/dev/null
    sudo chmod 600 /etc/wireguard/publickey

    # Store the new public key in Azure Key Vault
    VM_PUBLIC_KEY=$(cat /etc/wireguard/publickey)
    if [[ -n "$VM_PUBLIC_KEY" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-publickey" --value "$VM_PUBLIC_KEY" >/dev/null
        echo "Stored VM public key in Key Vault."
    fi

    # Store the new private key in Azure Key Vault
    VM_PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
    if [[ -n "$VM_PRIVATE_KEY" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-privatekey" --value "$VM_PRIVATE_KEY" >/dev/null
        echo "Stored VM private key in Key Vault."
    fi
fi

# Try to get the server public key from Key Vault
REMOTE_SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
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
if [[ -z "$REMOTE_ROUTER" ]]; then
    echo "No remoterouter found in Key Vault. Please ensure it is set up. IP:PORT or FQDN:PORT"
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

# Create a cron job to check for changes to the keys and update the config, only restart the service if key changes
CRON_SCRIPT="/usr/local/bin/update-wg-serverkey.sh"
sudo bash -c "cat > $CRON_SCRIPT << 'EOS'
#!/bin/bash
KEYVAULT_NAME=\"$KEYVAULT_NAME\"
VM_NAME=\"$VM_NAME\"
VM_PRIVATE_KEY=\$(az keyvault secret show --vault-name \"$KEYVAULT_NAME\" --name \"${VM_NAME}-privatekey\" --query value -o tsv 2>/dev/null || echo "")
CURRENT_PRIVATE_KEY_FILE=\"/etc/wireguard/privatekey\"
if [[ -n \"$VM_PRIVATE_KEY\" ]]; then
    if [[ ! -f \"$CURRENT_PRIVATE_KEY_FILE\" ]] || [[ \"$VM_PRIVATE_KEY\" != \"\$(cat $CURRENT_PRIVATE_KEY_FILE)\" ]]; then
        echo \"$VM_PRIVATE_KEY\" | sudo tee \"$CURRENT_PRIVATE_KEY_FILE\" > /dev/null
        sudo chmod 600 \"$CURRENT_PRIVATE_KEY_FILE\"
        RESTART_WG=1
    fi
fi

VM_PUBLIC_KEY=\$(az keyvault secret show --vault-name \"$KEYVAULT_NAME\" --name \"${VM_NAME}-publickey\" --query value -o tsv 2>/dev/null || echo "")
CURRENT_PUBLIC_KEY_FILE=\"/etc/wireguard/publickey\"
if [[ -n \"$VM_PUBLIC_KEY\" ]]; then
    if [[ ! -f \"$CURRENT_PUBLIC_KEY_FILE\" ]] || [[ \"$VM_PUBLIC_KEY\" != \"\$(cat $CURRENT_PUBLIC_KEY_FILE)\" ]]; then
        echo \"$VM_PUBLIC_KEY\" | sudo tee \"$CURRENT_PUBLIC_KEY_FILE\" > /dev/null
        sudo chmod 600 \"$CURRENT_PUBLIC_KEY_FILE\"
        RESTART_WG=1
    fi
fi

SERVER_PUBLIC_KEY=\$(az keyvault secret show --vault-name \"$KEYVAULT_NAME\" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
if [[ -n \"$SERVER_PUBLIC_KEY\" ]]; then
    CURRENT_KEY_FILE=\"/etc/wireguard/remoteserverpublickey\"
    if [[ ! -f \"$CURRENT_KEY_FILE\" ]] || [[ \"$SERVER_PUBLIC_KEY\" != \"\$(cat $CURRENT_KEY_FILE)\" ]]; then
        echo \"$SERVER_PUBLIC_KEY\" | sudo tee \"$CURRENT_KEY_FILE\" > /dev/null
        RESTART_WG=1
    fi
fi

if [[ -n \"$RESTART_WG\" ]]; then
    echo "Restarting WireGuard service due to key changes..."
    sudo systemctl restart wg-quick@wg0
else
    echo "No key changes detected. WireGuard service remains running."
fi
echo "WireGuard keys updated and checked successfully."
EOS"

# Make the script executable
sudo chmod +x $CRON_SCRIPT

# Add cron job to run every 15 minutes
( sudo crontab -l 2>/dev/null; echo "*/15 * * * * $CRON_SCRIPT" ) | sudo crontab -

echo "WireGuard installation and setup complete."

# Copy the firstboot.sh script to /home/azureuser/ only if not already running from there
if [[ "$SCRIPT_PATH" != "/home/azureuser/firstboot.sh" ]]; then
    sudo cp /c:/Users/aarosanders/Desktop/wiregaurdNVA/new/firstboot.sh /home/azureuser/
    sudo chown azureuser:azureuser /home/azureuser/firstboot.sh
fi

# End of script