@description('Name of the Virtual Network')
var vnetName = 'WGNVA-VNet'

@description('Address space for the Virtual Network')
var vnetAddressSpace = '100.127.0.0/16'

@description('Subnet name')
var subnetName = 'WGNVA'

@description('Subnet address prefix')
var subnetAddressPrefix  = '100.127.0.0/24'

@description('Base name for the Key Vault')
param keyVaultBaseName string = 'WGNVAKeyVault'

@description('Generated unique suffix')
var keyVaultSuffix = substring(string(uniqueString(resourceGroup().id, keyVaultBaseName)), 0, 5)

@description('Deterministic Key Vault name')
var keyVaultName = '${keyVaultBaseName}-${keyVaultSuffix}'

@description('Name of the Virtual Machine')
var vmName = 'WireGuardNVA'

@description('Name of the secret to store the admin password')
var adminPasswordSecretName = 'WGNVAadminPassword'

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Select the VM SKU')
param vmSku string = 'Standard_F2as_v6'

@description('Ubuntu 20.04 LTS Gen2 image reference')
var ubuntuImage = {
  publisher: 'canonical'
  offer: '0001-com-ubuntu-server-focal'
  sku: '20_04-lts-gen2'
  version: 'latest'
}

@description('Randomly generated admin password')
@secure()
param adminPassword string = newGuid()

// @description('Cloud-init script to download and execute firstboot.sh')
// var cloudInit = '''
// #cloud-config
// runcmd:
//   - curl -o /tmp/firstboot.sh -L 'https://raw.githubusercontent.com/MicrosoftAzureAaron/BicepWireGaurdNVA/main/firstboot.sh'
//   - chmod +x /tmp/firstboot.sh
//   - /tmp/firstboot.sh
// '''

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: resourceGroup().location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: 'ebf6d9f4-8eb2-4d5e-aeac-f2b32d8f12f2' // Your Azure AD object ID
        permissions: {
          secrets: [
            'get'
            'set'
            'list'
          ]
        }
      }
      // Add VM managed identity access policy
      {
        tenantId: subscription().tenantId
        objectId: vm.identity.principalId // VM's managed identity
        permissions: {
          secrets: [
            'get'
            'set'           
            'list'
          ]
        }
      }
    ]
  }
}

resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault // Simplified syntax using the parent property
  name: adminPasswordSecretName
  properties: {
    value: adminPassword // Store the evaluated value of adminPassword
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: resourceGroup().location
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned' // Enable system-assigned managed identity
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSku
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      //customData: base64(cloudInit) // Pass the cloud-init script as base64-encoded data
    }
    storageProfile: {
      imageReference: ubuntuImage
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
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
      commandToExecute: 'bash firstboot.sh'
    }
  }
}

resource routeTable 'Microsoft.Network/routeTables@2023-02-01' = {
  name: 'WGRouteTable'
  location: resourceGroup().location
  properties: {
    routes: [
      {
        name: 'HomeLANRoute'
        properties: {
          addressPrefix: '192.168.1.0/24'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nic.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource subnetRouteTableAssoc 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    routeTable: {
      id: routeTable.id
    }
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: '${vmName}-publicIP'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
