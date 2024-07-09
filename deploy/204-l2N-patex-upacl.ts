
import { DeployFunction } from 'hardhat-deploy/dist/types'

// const { ethers } = require('hardhat');
// const { getNamedAccounts, deployments } = require('hardhat-deploy');

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('Patex')).address;
    const proxyAddress = (await deployments.get('PatexProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('Patex', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _gasContract = "0x17ca24570E9A78e1A3B72f81c61b13D08CE541cD"
    const initializeData = proxy.interface.encodeFunctionData('initialize', [_gasContract]);

    // Update the proxy to point to the new implementation and call initialize
    await execute(
        'ProxyAdmin',
        { 
          from: deployer 
        },
        'upgradeAndCall',
        proxyAddress,
        implAddress,
        initializeData
    );

    console.log('proxyAddress', proxyAddress);
    console.log('implAddress', implAddress);
    console.log('initializeData', initializeData);

      //  // Get the implementation address
      //  const impAddress = await ProxyAdmin.getProxyImplementation(proxyAddress);
      //  // Get the admin address
      //  const adminAddress = await ProxyAdmin.getProxyAdmin(proxyAddress);
    
      //  console.log('Proxy address:', proxyAddress);
      //  console.log('Current implementation address:', impAddress);
      //  console.log('Current admin address:', adminAddress);
    
}

deployFn.tags = ['l2PatexUpcal']

export default deployFn

