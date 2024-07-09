import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {

    const _SHARES = (await deployments.get('SharesProxy')).address;

    await deploy({
        hre,
        name: 'WETHRebasing',
        args: [_SHARES],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l2WETHRebasingProxyImpl']

export default deployFn
