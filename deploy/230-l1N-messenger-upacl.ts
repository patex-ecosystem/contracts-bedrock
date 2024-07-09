
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const implAddress = (await deployments.get('L1CrossDomainMessenger')).address;
    const proxyAddress = (await deployments.get('Proxy__PVM_L1CrossDomainMessenger')).address;
    const proxyAdminAddress = (await deployments.get('ProxyAdmin')).address;

    const proxy = await ethers.getContractAt('L1CrossDomainMessenger', proxyAddress);
    const ProxyAdmin = await ethers.getContractAt('ProxyAdmin', proxyAdminAddress);

    const _portal = "0xD7400A9E3bd054264be87443939770dcf23E5b95"

    const initializeData = proxy.interface.encodeFunctionData('initialize', [
        _portal
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

deployFn.tags = ['l1MessengerUpcal']

export default deployFn

