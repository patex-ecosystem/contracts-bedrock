import { DeployFunction } from 'hardhat-deploy/dist/types'
import '@eth-patex/hardhat-deploy-config'
import '@nomiclabs/hardhat-ethers'
import { ethers } from 'ethers'

import { assertContractVariable, deploy } from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {


  /**
   * IMPORTANT: Before custom re-deploy set correct fee RECIPIENT address
   **/
  const baseFeeVaultRecipient = '0x0000000000000000000000000000000000000000'
  if (baseFeeVaultRecipient === ethers.constants.AddressZero) {
    throw new Error('BaseFeeVault RECIPIENT undefined')
  }

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

deployFn.tags = ['BaseFeeVaultImplTmp', 'l2BaseFeeVaultImplTmp']

export default deployFn
