
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('PatexPortal')).address;
    const proxyAddress = (await deployments.get('PatexPortalProxy')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('PatexPortal', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);
 
    const _l2Oracle = "0x77daF3f9aC6Cfe26ad8669EC95b8A4F6ab810E72"
    const _guardian = deployer
    const _systemConfig = "0x95eb0167854a4A342ae5B6636Afa4015E13F67fD"
    const _paused = false
    const _yieldManager = "0x16Cc7b51de361A845AD070ed6E792b2BB720f8c6"
    const _postdeploys = "0xDfda5a9e7F34AE310c3DFC8505558348Ae0200c4"

    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _l2Oracle,
        _guardian,
        _systemConfig,
        _paused,
        _yieldManager,
        _postdeploys
    ]);

    // Update the proxy to point to the new implementation and call initialize
    // await execute(
    //     'ProxyAdmin',
    //     { 
    //       from: deployer 
    //     },
    //     'upgradeAndCall',
    //     proxyAddress,
    //     implAddress,
    //     initializeData
    // );

    await ProxyAdmin.upgradeAndCall(proxyAddress, implAddress, initializeData)

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

deployFn.tags = ['l1PortalUpcal']

export default deployFn

