@description('Name of the Virtual Network')
var vnetName = 'WGNVA-VNet'

@description('Address space for the Virtual Network')
var vnetAddressSpace = '100.127.0.0/16'

@description('Subnet name')
var subnetName = 'WGNVA'

@description('Subnet address prefix')
var subnetAddressPrefix = '100.127.0.0/24'

@description('Base name for the Key Vault')
param keyVaultBaseName string ='WGNVAKeyVault'


@description('Generated GUID for unique suffix')
param generatedGuid string = newGuid()
param uniqueSuffix string = uniqueString(generatedGuid)
param keyVaultSuffix string = substring(uniqueSuffix, 0, 5)

@description('Deterministic Key Vault name')
var keyVaultName = '${keyVaultBaseName}-${keyVaultSuffix}'

@description('Name of the secret to store the admin password')
var adminPasswordSecretName = 'WGNVAadminPassword'

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Name of the Virtual Machine')
var vmName = 'WireGuardNVA'

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
        objectId: 'ebf6d9f4-8eb2-4d5e-aeac-f2b32d8f12f2' // Replace with your Azure AD object ID
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
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: vmSku
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
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
  }
}
