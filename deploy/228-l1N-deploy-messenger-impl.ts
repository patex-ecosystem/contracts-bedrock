import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {


    await deploy({
        hre,
        name: 'L1CrossDomainMessenger',
        args: [],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l1CrossDomainMessengerImpl']

export default deployFn
