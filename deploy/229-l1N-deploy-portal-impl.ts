import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {

    await deploy({
        hre,
        name: 'PatexPortal',
        args: [],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l1PatexPortalImpl']

export default deployFn
