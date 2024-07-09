
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('WETHRebasing')).address;
    const proxyAddress = (await deployments.get('WETHRebasingProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('WETHRebasing', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _postdeploys = (await deployments.get('Lib_Postdeploys')).address;

    const initializeData = proxy.interface.encodeFunctionData('initialize', [_postdeploys]);

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
}

deployFn.tags = ['l2WethUpcal']

export default deployFn

