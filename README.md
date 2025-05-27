# BicepWireGuardNVA

This repo stores a deployment that creates a VNET with an NVA and a WireGuard tunnel NVA.

The deployment provisions all resources for the first time, including:
- User Assigned Managed Identity for the VM
- VNET
- Key Vault and Private Endpoint
- VM
- Public IP
- Startup script to store all information in the Key Vault

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FGreenField.json)

---

To deploy just the WireGuard NVA VM (assuming all other information is already stored in the Key Vault):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FBrownField.json)
