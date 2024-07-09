import { DeployFunction } from 'hardhat-deploy/dist/types'

const { deployments, getNamedAccounts } = require('hardhat');

import {
    deploy,
    getContractFromArtifact,
  } from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();

    const _patexConfigurationContract = (await deployments.get('PatexProxy')).address;
    const _patexFeeVault = "0x4200000000000000000000000000000000000019";

    await deploy({
        hre,
        name: 'Gas',
        args: [deployer, _patexConfigurationContract, _patexFeeVault],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l2GasImpl']

export default deployFn
