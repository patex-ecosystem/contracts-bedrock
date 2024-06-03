import { DeployFunction } from 'hardhat-deploy/dist/types'
import '@eth-patex/hardhat-deploy-config'
import '@nomiclabs/hardhat-ethers'
import { ethers } from 'ethers'

import { assertContractVariable, deploy } from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

  /**
   * IMPORTANT: Before custom re-deploy set correct fee RECIPIENT address
  **/
  const l1FeeVaultRecipient= '0x89a2Cde14eCA522D5477C1AEE617039e4d0eeb60'
//   if (l1FeeVaultRecipient === ethers.constants.AddressZero) {
//     throw new Error('L1FeeVault RECIPIENT undefined')
//   }

  await deploy({
    hre,
    name: 'L1FeeVault',
    args: [l1FeeVaultRecipient],
    postDeployAction: async (contract) => {
      await assertContractVariable(
        contract,
        'RECIPIENT',
        ethers.utils.getAddress(l1FeeVaultRecipient)
      )
    },
  })
}

deployFn.tags = ['L1FeeVaultImplTmp', 'l2L1FeeVaultImplTmpСС']

export default deployFn
