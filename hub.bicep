targetScope = 'subscription'

@allowed([
  'eastus2'
  'canadaeast'
  'canadacentral'
])
param location string = 'eastus2'

param vnetAddressPrefix string = '10.0.0.0/16'

param subnetJumpboxAddressPrefix string = '10.0.1.0/27'

@secure()
param username string

@secure()
param password string

/* Resource group */
resource rg 'Microsoft.Resources/resourceGroups@2025-03-01' = {
  name: 'rg-hub'
  location: location
}

var suffix = uniqueString(rg.id)

/* Hub network */

module nsgJumpbox 'br/public:avm/res/network/network-security-group:0.5.1' = {
  scope: rg
  params: {
    name: 'nsg-agent'
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.7.0' = {
  scope: rg
  params: {
    name: 'vnet-hub'
    location: location
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: 'snet-jumpbox'
        addressPrefix: subnetJumpboxAddressPrefix
        networkSecurityGroupResourceId: nsgJumpbox.outputs.resourceId
      }
    ]
  }
}

/* Firewall */

module azureFirewall 'br/public:avm/res/network/azure-firewall:0.6.1' = {
  scope: rg
  params: {
    name: 'fw-${suffix}'
    azureSkuTier: 'Basic'
    location: location
    networkRuleCollections: []
    threatIntelMode: 'Deny'
    virtualNetworkResourceId: vnet.outputs.resourceId
  }
}

/*  Route table */

module routeTable 'br/public:avm/res/network/route-table:0.4.1' = {
  scope: rg
  params: {
    name: 'rt-firewall'
    routes: [
      {
        name: 'all-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewall.outputs.privateIp
        }
      }
    ]
  }
}

/* Jumpbox windows */
module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.15.0' = {
  scope: rg
  params: {
    // Required parameters
    adminUsername: username
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    name: 'cvmwinmin'
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'jumpboxconfig'
            subnetResourceId: vnet.outputs.subnetResourceIds[0]
          }
        ]
        nicSuffix: 'jumpbox-nic-01'
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    osType: 'Windows'
    vmSize: 'Standard_D2s_v3'
    zone: 0
    // Non-required parameters
    adminPassword: password
    location: location
  }
}
