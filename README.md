# BicepWireGuardNVA

This repo stores a deployment that creates a VNET with an NVA and a WireGuard tunnel NVA.

The deployment provisions all resources for the first time, including:
- User Assigned Managed Identity for the VM
- VNET
- Key Vault and Private Endpoint with Linked Private DNS zone
- Wiregaurd NVA VM
- OS Disk
- NIC
- Public IP
- Startup script to store all information in the Key Vault

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FGreenField.json)

After this runs you must add the following secrets to your Key Vault manually. 
- remoterouter
- remoteserverpublickey

---

Deploy the WireGuard NVA VM (assuming all other resources still exist):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FBrownField.json)


--

Deploy the WireGuard NVA VM with a new disk(assuming all other resources still exist):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FPurpleField.json)
