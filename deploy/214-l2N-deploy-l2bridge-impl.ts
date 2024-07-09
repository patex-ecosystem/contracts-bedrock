import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    await deploy({
        hre,
        name: 'L2PatexBridge',
        args: [],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l2BridgeImpl']

export default deployFn
