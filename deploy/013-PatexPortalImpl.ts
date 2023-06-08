import { DeployFunction } from 'hardhat-deploy/dist/types'
import '@eth-patex/hardhat-deploy-config'

import {
  assertContractVariable,
  deploy,
  getContractFromArtifact,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {
  const { deployer } = await hre.getNamedAccounts()
  const isLiveDeployer =
    deployer.toLowerCase() === hre.deployConfig.controller.toLowerCase()

  const L2OutputOracleProxy = await getContractFromArtifact(
    hre,
    'L2OutputOracleProxy'
  )

  const Artifact__SystemConfigProxy = await hre.deployments.get(
    'SystemConfigProxy'
  )

  const portalGuardian = hre.deployConfig.portalGuardian
  const portalGuardianCode = await hre.ethers.provider.getCode(portalGuardian)
  if (portalGuardianCode === '0x') {
    console.log(
      `WARNING: setting PatexPortal.GUARDIAN to ${portalGuardian} and it has no code`
    )
    // if (!isLiveDeployer) {
    //   throw new Error(
    //     'Do not deploy to production networks without the GUARDIAN being a contract'
    //   )
    // }
  }

  // Deploy the PatexPortal implementation as paused to
  // ensure that users do not interact with it and instead
  // interact with the proxied contract.
  // The `portalGuardian` is set at the GUARDIAN.
  await deploy({
    hre,
    name: 'PatexPortal',
    args: [
      L2OutputOracleProxy.address,
      portalGuardian,
      true, // paused
      Artifact__SystemConfigProxy.address,
    ],
    postDeployAction: async (contract) => {
      await assertContractVariable(
        contract,
        'L2_ORACLE',
        L2OutputOracleProxy.address
      )
      await assertContractVariable(
        contract,
        'GUARDIAN',
        hre.deployConfig.portalGuardian
      )
      await assertContractVariable(
        contract,
        'SYSTEM_CONFIG',
        Artifact__SystemConfigProxy.address
      )
    },
  })
}

deployFn.tags = ['PatexPortalImpl', 'setup', 'l1']

export default deployFn
