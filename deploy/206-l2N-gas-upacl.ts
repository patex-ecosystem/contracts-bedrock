
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('Gas')).address;
    const proxyAddress = (await deployments.get('GasProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('Gas', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _zeroClaimRate = "0x0"
    const _baseGasSeconds =  "0x1"
    const _baseClaimRate = "0x1388"
    const _ceilGasSeconds = "0x278d00"
    const _ceilClaimRate = "0x2710"

    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _zeroClaimRate,
        _baseGasSeconds,
        _baseClaimRate,
        _ceilGasSeconds,
        _ceilClaimRate
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

    //    // Get the implementation address
    //    const impAddress = await ProxyAdmin.getProxyImplementation(proxyAddress);
    //    // Get the admin address
    //    const adminAddress = await ProxyAdmin.getProxyAdmin(proxyAddress);
    
    //    console.log('Proxy address:', proxyAddress);
    //    console.log('Current implementation address:', impAddress);
    //    console.log('Current admin address:', adminAddress);
    
}

deployFn.tags = ['l2GasUpcal']

export default deployFn

