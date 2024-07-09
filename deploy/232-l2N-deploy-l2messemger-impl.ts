import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const _l1CrossDomainMessenger = "0xBdBeA7f90c8E234a1edA6948d9F772D4c50f5bD5"

    await deploy({
        hre,
        name: 'L2CrossDomainMessenger',
        args: [_l1CrossDomainMessenger],
        postDeployAction: async (contract) => {},
    })
}

deployFn.tags = ['l2MessengerImpl']

export default deployFn
