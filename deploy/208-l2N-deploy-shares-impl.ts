import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const reporter = "0x16Cc7b51de361A845AD070ed6E792b2BB720f8c6" // ETHYieldManager

    await deploy({
        hre,
        name: 'Shares',
        args: [reporter],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l2SharesImpl']

export default deployFn
