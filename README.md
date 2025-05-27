# BicepWireGaurdNVA
this repo is to store a deployment, which creates a VNET with a NVA and wiregaurd tunnel NVA  

This deploys all resources for the first time. User Assign Managed Identity for the VM, VNET, Key Vault and PE, VM, Public IP, and runs the start up script to store all information in the key vault.
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FGreenField.json)


This is deploys just the Wiregaurd NVA VM, assumes all other information is stored in the key vault. 
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FBrownField.json)
