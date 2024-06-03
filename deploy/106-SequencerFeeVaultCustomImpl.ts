import { DeployFunction } from 'hardhat-deploy/dist/types'
import '@eth-patex/hardhat-deploy-config'
import '@nomiclabs/hardhat-ethers'
import { ethers } from 'ethers'

import { assertContractVariable, deploy } from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

  /**
   * IMPORTANT: Before custom re-deploy set correct fee RECIPIENT address
   **/
  const sequencerFeeVaultRecipient = '0x89a2Cde14eCA522D5477C1AEE617039e4d0eeb60'
//   if (sequencerFeeVaultRecipient === ethers.constants.AddressZero) {
//     throw new Error(`SequencerFeeVault RECIPIENT undefined`)
//   }

  await deploy({
    hre,
    name: 'SequencerFeeVault',
    args: [sequencerFeeVaultRecipient],
    postDeployAction: async (contract) => {
      await assertContractVariable(
          contract,
          'RECIPIENT',
          ethers.utils.getAddress(sequencerFeeVaultRecipient)
      )
    },
  })
}

deployFn.tags = ['SequencerFeeVaultImplTmp', 'l2SequencerFeeVaultImplTmpСС']

export default deployFn