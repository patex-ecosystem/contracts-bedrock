import { DeployFunction } from 'hardhat-deploy/dist/types'

import {
  assertContractVariable,
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {
  const PatexPortalProxy = await getContractFromArtifact(
    hre,
    'PatexPortalProxy'
  )

  await deploy({
    hre,
    name: 'PortalSender',
    args: [PatexPortalProxy.address],
    postDeployAction: async (contract) => {
      await assertContractVariable(
        contract,
        'PORTAL',
        PatexPortalProxy.address
      )
    },
  })
}

deployFn.tags = ['PortalSenderImpl', 'setup', 'l1']

export default deployFn
