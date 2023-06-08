import { DeployFunction } from 'hardhat-deploy/dist/types'
import { ethers } from 'ethers'
import '@eth-patex/hardhat-deploy-config'
import '@nomiclabs/hardhat-ethers'

import { assertContractVariable, deploy } from '../src/deploy-utils'
import { predeploys } from '../src/constants'

const deployFn: DeployFunction = async (hre) => {
  const PatexMintableERC721Factory = await hre.ethers.getContractAt(
    'PatexMintableERC721Factory',
    predeploys.PatexMintableERC721Factory
  )
  const remoteChainId = await PatexMintableERC721Factory.REMOTE_CHAIN_ID()

  await deploy({
    hre,
    name: 'PatexMintableERC721Factory',
    args: [predeploys.L2StandardBridge, remoteChainId],
    postDeployAction: async (contract) => {
      await assertContractVariable(
        contract,
        'BRIDGE',
        ethers.utils.getAddress(predeploys.L2StandardBridge)
      )
      await assertContractVariable(contract, 'REMOTE_CHAIN_ID', remoteChainId)
    },
  })
}

deployFn.tags = ['PatexMintableERC721FactoryImpl', 'l2']

export default deployFn
