#!/bin/bash
RESTART_WG=0
KEYVAULT_NAME="$KEYVAULT_NAME"
VM_NAME="$VM_NAME"

# Compare and update private key
VM_PRIVATE_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-privatekey" --query value -o tsv 2>/dev/null || echo "")
CURRENT_PRIVATE_KEY=$(cat /etc/wireguard/privatekey 2>/dev/null || echo "")
if [[ "$VM_PRIVATE_KEY" != "$CURRENT_PRIVATE_KEY" && -n "$VM_PRIVATE_KEY" ]]; then
    echo "[update-wg-serverkey.sh] Private key changed, updating file and will restart WireGuard."
    echo "$VM_PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey > /dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    RESTART_WG=1
fi

# Compare and update public key
VM_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-publickey" --query value -o tsv 2>/dev/null || echo "")
CURRENT_PUBLIC_KEY=$(cat /etc/wireguard/publickey 2>/dev/null || echo "")
if [[ "$VM_PUBLIC_KEY" != "$CURRENT_PUBLIC_KEY" && -n "$VM_PUBLIC_KEY" ]]; then
    echo "[update-wg-serverkey.sh] Public key changed, updating file and will restart WireGuard."
    echo "$VM_PUBLIC_KEY" | sudo tee /etc/wireguard/publickey > /dev/null
    sudo chmod 600 /etc/wireguard/publickey
    RESTART_WG=1
fi

# Compare and update remote server public key
SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
CURRENT_SERVER_KEY=$(cat /etc/wireguard/remoteserverpublickey 2>/dev/null || echo "")
if [[ "$SERVER_PUBLIC_KEY" != "$CURRENT_SERVER_KEY" && -n "$SERVER_PUBLIC_KEY" ]]; then
    echo "[update-wg-serverkey.sh] Remote server public key changed, updating file and will restart WireGuard."
    echo "$SERVER_PUBLIC_KEY" | sudo tee /etc/wireguard/remoteserverpublickey > /dev/null
    sudo chmod 600 /etc/wireguard/remoteserverpublickey
    RESTART_WG=1
fi

if [[ $RESTART_WG -eq 1 ]]; then
    echo "[update-wg-serverkey.sh] Restarting WireGuard service due to key changes..."
    sudo systemctl restart wg-quick@wg0
else
    echo "[update-wg-serverkey.sh] No key changes detected. WireGuard service remains running."
fi
echo "[update-wg-serverkey.sh] WireGuard keys checked successfully."