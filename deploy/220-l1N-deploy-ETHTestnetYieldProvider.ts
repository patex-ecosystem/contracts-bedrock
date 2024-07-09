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
  const _owner = deployer
  const _token = "0x0000000000000000000000000000000000000000"

  await deploy({
    hre,
    name: 'ETHTestnetYieldProvider',
    args: [_yieldManager, _owner, _token],
    postDeployAction: async (contract) => {},
  })
}

deployFn.tags = ['l1ETHTestnetYieldProvider']

export default deployFn
