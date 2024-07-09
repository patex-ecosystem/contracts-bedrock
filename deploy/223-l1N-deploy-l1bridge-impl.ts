import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    await deploy({
        hre,
        name: 'L1PatexBridge',
        args: [],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l1BridgeImpl']

export default deployFn
