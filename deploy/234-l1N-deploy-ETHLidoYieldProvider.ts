import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  assertContractVariable,
  deploy,
  getDeploymentAddress,
} from '../src/deploy-utils'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

const deployFn: DeployFunction = async (hre) => {
    
  const { deployer } = await getNamedAccounts()

  const _yieldManager = (await deployments.get('ETHYieldManagerProxy')).address

  await deploy({
    hre,
    name: 'LidoYieldProvider',
    args: [_yieldManager],
    postDeployAction: async (contract) => {},
  })
}

deployFn.tags = ['l1LidoYieldProvider']

export default deployFn
