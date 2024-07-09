
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('ETHYieldManager')).address;
    const proxyAddress = (await deployments.get('ETHYieldManagerProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('ETHYieldManager', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _postdeploys = (await deployments.get('Lib_Postdeploys')).address;
    const _portal = "0xD7400A9E3bd054264be87443939770dcf23E5b95"

    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _portal,
        deployer,
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

deployFn.tags = ['l1ETHYieldManagerUpcal']

export default deployFn

