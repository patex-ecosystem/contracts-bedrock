import { DeployFunction } from 'hardhat-deploy/dist/types'
import '@eth-patex/hardhat-deploy-config'
import '@nomiclabs/hardhat-ethers'
import { ethers } from 'ethers'

import { assertContractVariable, deploy } from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {


  /**
   * IMPORTANT: Before custom re-deploy set correct fee RECIPIENT address
   **/
  const baseFeeVaultRecipient = '0x89a2Cde14eCA522D5477C1AEE617039e4d0eeb60'
//   if (baseFeeVaultRecipient === ethers.constants.AddressZero) {
//     throw new Error('BaseFeeVault RECIPIENT undefined')
//   }

  await deploy({
    hre,
    name: 'BaseFeeVault',
    args: [baseFeeVaultRecipient],
    postDeployAction: async (contract) => {
      await assertContractVariable(
        contract,
        'RECIPIENT',
        ethers.utils.getAddress(baseFeeVaultRecipient)
      )
    },
  })
}

deployFn.tags = ['BaseFeeVaultImplTmp', 'l2BaseFeeVaultImplTmpСС']

export default deployFn