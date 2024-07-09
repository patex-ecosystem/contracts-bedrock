
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('L1PatexBridge')).address;
    const proxyAddress = (await deployments.get('L1PatexBridgeProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('L1PatexBridge', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _portal = "0xD7400A9E3bd054264be87443939770dcf23E5b95"
    const _messenger = "0xBdBeA7f90c8E234a1edA6948d9F772D4c50f5bD5"
    const _usdYieldManager = "0x0000000000000000000000000000000000000000"
    const _ethYieldManager = (await deployments.get('ETHYieldManagerProxy')).address;
    const _postdeploys = (await deployments.get('Lib_Postdeploys')).address;
    const _otherBridge = "0x35FbeAb87d6252802Fc325d6C6AE2e6e758dd76D" // Deployed L2PatexBridgeProxy 
    
    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _portal,
        _messenger,
        _usdYieldManager,
        _ethYieldManager,
        _postdeploys,
        _otherBridge
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

deployFn.tags = ['l1BridgeUpcal']

export default deployFn

