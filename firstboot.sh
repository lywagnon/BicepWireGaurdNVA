#!/bin/bash

# Update the package list
echo "Updating package list..."
sudo apt-get update -y

# Upgrade installed packages
echo "Upgrading installed packages..."
sudo apt-get upgrade -y

# Install WireGuard
echo "Installing WireGuard..."
sudo apt-get install -y wireguard

# Enable and start the WireGuard service
echo "Enabling and starting WireGuard service..."
sudo systemctl enable wg-quick@wg0
#sudo systemctl start wg-quick@wg0

echo "WireGuard installation and setup complete."