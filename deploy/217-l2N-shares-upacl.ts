
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('Shares')).address;
    const proxyAddress = (await deployments.get('SharesProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('Shares', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _price = "0x3b9aca00"
    const _postdeploys = (await deployments.get('Lib_Postdeploys')).address;

    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _price,
        _postdeploys
    ]);

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

deployFn.tags = ['l2SharesUpcal']

export default deployFn

