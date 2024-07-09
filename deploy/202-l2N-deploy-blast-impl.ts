import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const YIELD_CONTRACT = "0x0000000000000000000000000000000000000100"

    await deploy({
        hre,
        name: 'Patex',
        args: [YIELD_CONTRACT],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l2PatexImpl']

export default deployFn
