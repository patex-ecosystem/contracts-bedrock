
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = "0x84109fC3a64E6038EfF84354531acAB01bd4A1EA";
    const proxyAddress = "0x4200000000000000000000000000000000000007";
    const proxyAdminAddress = "0x4200000000000000000000000000000000000018";

    const proxy = await ethers.getContractAt('L2CrossDomainMessenger', proxyAddress);
    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _postdeploys = (await deployments.get('Lib_Postdeploys')).address;
   
    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _postdeploys
    ]);

    // // Update the proxy to point to the new implementation and call initialize
    // await execute(
    //     'ProxyAdmin',
    //     { 
    //       from: deployer 
    //     },
    //     'upgradeToAndCall',
    //     proxyAddress,
    //     implAddress,
    //     initializeData
    // );

    await proxyAdmin.upgradeAndCall(proxyAddress, implAddress, initializeData)

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

deployFn.tags = ['l2MessengerUpcal']

export default deployFn

