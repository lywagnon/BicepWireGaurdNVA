@description('Select the VM SKU')
param vmSku string = 'Standard_F2as_v6'

@description('Name of the Virtual Machine')
param vmName string = 'WireGuardNVA'

@description('Name of the existing user-assigned managed identity')
var userAssignedIdentityName = 'WireGaurdNVAMI'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

// Reference existing NIC from Greenfield deployment
resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' existing = {
  name: '${vmName}-nic'
}

// Reference existing OS disk from Greenfield deployment
resource osDisk 'Microsoft.Compute/disks@2022-07-02' existing = {
  name: '${vmName}_OsDisk_1_84b137d0ae6840658df7553f49ac6c93'
}

// Deploy VM using existing NIC and OS disk
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSku
    }
    storageProfile: {
      osDisk: {
        osType: 'Linux'
        managedDisk: {
          id: osDisk.id
        }
        createOption: 'Attach'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: null // Use a managed storage account
      }
    }
  }
}

// Custom Script Extension to configure WireGuard
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: 'customScript'
  location: resourceGroup().location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/MicrosoftAzureAaron/BicepWireGaurdNVA/main/firstboot.sh'
      ]
      commandToExecute: 'sudo bash firstboot.sh'
    }
  }
}
