import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {

    const _yieldManager = (await deployments.get('ETHYieldManagerProxy')).address;

    await deploy({
        hre,
        name: 'Insurance',
        args: [_yieldManager],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l1InsuranceImpl']

export default deployFn
