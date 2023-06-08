import assert from 'assert'

import { ethers } from 'ethers'
import { DeployFunction } from 'hardhat-deploy/dist/types'
import { awaitCondition } from '@eth-patex/core-utils'
import '@eth-patex/hardhat-deploy-config'
import 'hardhat-deploy'
import '@nomiclabs/hardhat-ethers'

import {
  assertContractVariable,
  getContractsFromArtifacts,
  printJsonTransaction,
  isStep,
  doStep,
  printTenderlySimulationLink,
  printCastCommand,
  liveDeployer,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {
  const { deployer } = await hre.getNamedAccounts()

  // Set up required contract references.
  const [
    SystemDictator,
    ProxyAdmin,
    AddressManager,
    L1CrossDomainMessenger,
    L1StandardBridgeProxy,
    L1StandardBridge,
    L2OutputOracle,
    PatexPortal,
    PatexMintableERC20Factory,
    L1ERC721Bridge,
  ] = await getContractsFromArtifacts(hre, [
    {
      name: 'SystemDictatorProxy',
      iface: 'SystemDictator',
      signerOrProvider: deployer,
    },
    {
      name: 'ProxyAdmin',
      signerOrProvider: deployer,
    },
    {
      name: 'Lib_AddressManager',
      signerOrProvider: deployer,
    },
    {
      name: 'Proxy__PVM_L1CrossDomainMessenger',
      iface: 'L1CrossDomainMessenger',
      signerOrProvider: deployer,
    },
    {
      name: 'Proxy__PVM_L1StandardBridge',
    },
    {
      name: 'Proxy__PVM_L1StandardBridge',
      iface: 'L1StandardBridge',
      signerOrProvider: deployer,
    },
    {
      name: 'L2OutputOracleProxy',
      iface: 'L2OutputOracle',
      signerOrProvider: deployer,
    },
    {
      name: 'PatexPortalProxy',
      iface: 'PatexPortal',
      signerOrProvider: deployer,
    },
    {
      name: 'PatexMintableERC20FactoryProxy',
      iface: 'PatexMintableERC20Factory',
      signerOrProvider: deployer,
    },
    {
      name: 'L1ERC721BridgeProxy',
      iface: 'L1ERC721Bridge',
      signerOrProvider: deployer,
    },
  ])

  // If we have the key for the controller then we don't need to wait for external txns.
  // Set the DISABLE_LIVE_DEPLOYER=true in the env to ensure the script will pause to simulate scenarios
  // where the controller is not the deployer.
  const isLiveDeployer = await liveDeployer({
    hre,
    disabled: process.env.DISABLE_LIVE_DEPLOYER,
  })

  // Step 3 clears out some state from the AddressManager.
  await doStep({
    isLiveDeployer,
    SystemDictator,
    step: 3,
    message: `
      Step 3 will clear out some legacy state from the AddressManager. Once you execute this step,
      you WILL NOT BE ABLE TO RESTART THE SYSTEM using exit1(). You should confirm that the L2
      system is entirely operational before executing this step.
    `,
    checks: async () => {
      const deads = [
        'PVM_CanonicalTransactionChain',
        'PVM_L2CrossDomainMessenger',
        'PVM_DecompressionPrecompileAddress',
        'PVM_Sequencer',
        'PVM_Proposer',
        'PVM_ChainStorageContainer-CTC-batches',
        'PVM_ChainStorageContainer-CTC-queue',
        'PVM_CanonicalTransactionChain',
        'PVM_StateCommitmentChain',
        'PVM_BondManager',
        'PVM_ExecutionManager',
        'PVM_FraudVerifier',
        'PVM_StateManagerFactory',
        'PVM_StateTransitionerFactory',
        'PVM_SafetyChecker',
        'PVM_L1MultiMessageRelayer',
        'BondManager',
      ]
      for (const dead of deads) {
        const addr = await AddressManager.getAddress(dead)
        assert(addr === ethers.constants.AddressZero)
      }
    },
  })

  // Step 4 transfers ownership of the AddressManager and L1StandardBridge to the ProxyAdmin.
  await doStep({
    isLiveDeployer,
    SystemDictator,
    step: 4,
    message: `
      Step 4 will transfer ownership of the AddressManager and L1StandardBridge to the ProxyAdmin.
    `,
    checks: async () => {
      await assertContractVariable(AddressManager, 'owner', ProxyAdmin.address)

      assert(
        (await L1StandardBridgeProxy.callStatic.getOwner({
          from: ethers.constants.AddressZero,
        })) === ProxyAdmin.address
      )
    },
  })

  // Make sure the dynamic system configuration has been set.
  if (
    (await isStep(SystemDictator, 5)) &&
    !(await SystemDictator.dynamicConfigSet())
  ) {
    console.log(`
      You must now set the dynamic L2OutputOracle configuration by calling the function
      updateL2OutputOracleDynamicConfig. You will need to provide the
      l2OutputOracleStartingBlockNumber and the l2OutputOracleStartingTimestamp which can both be
      found by querying the last finalized block in the L2 node.
    `)

    if (isLiveDeployer) {
      console.log(`Updating dynamic oracle config...`)

      // Use default starting time if not provided
      let deployL2StartingTimestamp =
        hre.deployConfig.l2OutputOracleStartingTimestamp
      if (deployL2StartingTimestamp < 0) {
        const l1StartingBlock = await hre.ethers.provider.getBlock(
          hre.deployConfig.l1StartingBlockTag
        )
        if (l1StartingBlock === null) {
          throw new Error(
            `Cannot fetch block tag ${hre.deployConfig.l1StartingBlockTag}`
          )
        }
        deployL2StartingTimestamp = l1StartingBlock.timestamp
      }

      await SystemDictator.updateDynamicConfig(
        {
          l2OutputOracleStartingBlockNumber:
            hre.deployConfig.l2OutputOracleStartingBlockNumber,
          l2OutputOracleStartingTimestamp: deployL2StartingTimestamp,
        },
        false // do not pause the the PatexPortal when initializing
      )
    } else {
      // pause the PatexPortal when initializing
      const patexPortalPaused = true
      const tx = await SystemDictator.populateTransaction.updateDynamicConfig(
        {
          l2OutputOracleStartingBlockNumber:
            hre.deployConfig.l2OutputOracleStartingBlockNumber,
          l2OutputOracleStartingTimestamp:
            hre.deployConfig.l2OutputOracleStartingTimestamp,
        },
        patexPortalPaused
      )
      console.log(`Please update dynamic oracle config...`)
      console.log(
        JSON.stringify(
          {
            l2OutputOracleStartingBlockNumber:
              hre.deployConfig.l2OutputOracleStartingBlockNumber,
            l2OutputOracleStartingTimestamp:
              hre.deployConfig.l2OutputOracleStartingTimestamp,
            patexPortalPaused,
          },
          null,
          2
        )
      )
      console.log(`MSD address: ${SystemDictator.address}`)
      printJsonTransaction(tx)
      printCastCommand(tx)
      await printTenderlySimulationLink(SystemDictator.provider, tx)
    }

    await awaitCondition(
      async () => {
        return SystemDictator.dynamicConfigSet()
      },
      5000,
      1000
    )
  }

  // Step 5 initializes all contracts.
  await doStep({
    isLiveDeployer,
    SystemDictator,
    step: 5,
    message: `
      Step 5 will initialize all Bedrock contracts. After this step is executed, the PatexPortal
      will be open for deposits but withdrawals will be paused if deploying a production network.
      The Proposer will also be able to submit L2 outputs to the L2OutputOracle.
    `,
    checks: async () => {
      // Check L2OutputOracle was initialized properly.
      await assertContractVariable(
        L2OutputOracle,
        'latestBlockNumber',
        hre.deployConfig.l2OutputOracleStartingBlockNumber
      )

      // Check PatexPortal was initialized properly.
      await assertContractVariable(
        PatexPortal,
        'l2Sender',
        '0x000000000000000000000000000000000000dEaD'
      )
      const resourceParams = await PatexPortal.params()
      assert(
        resourceParams.prevBaseFee.eq(ethers.utils.parseUnits('1', 'gwei')),
        `PatexPortal was not initialized with the correct initial base fee`
      )
      assert(
        resourceParams.prevBoughtGas.eq(0),
        `PatexPortal was not initialized with the correct initial bought gas`
      )
      assert(
        !resourceParams.prevBlockNum.eq(0),
        `PatexPortal was not initialized with the correct initial block number`
      )
      assert(
        (await hre.ethers.provider.getBalance(L1StandardBridge.address)).eq(0)
      )

      if (isLiveDeployer) {
        await assertContractVariable(PatexPortal, 'paused', false)
      } else {
        await assertContractVariable(PatexPortal, 'paused', true)
      }

      // Check L1CrossDomainMessenger was initialized properly.
      try {
        await L1CrossDomainMessenger.xDomainMessageSender()
        assert(false, `L1CrossDomainMessenger was not initialized properly`)
      } catch (err) {
        // Expected.
      }

      // Check L1StandardBridge was initialized properly.
      await assertContractVariable(
        L1StandardBridge,
        'messenger',
        L1CrossDomainMessenger.address
      )
      assert(
        (await hre.ethers.provider.getBalance(L1StandardBridge.address)).eq(0)
      )

      // Check PatexMintableERC20Factory was initialized properly.
      await assertContractVariable(
        PatexMintableERC20Factory,
        'BRIDGE',
        L1StandardBridge.address
      )

      // Check L1ERC721Bridge was initialized properly.
      await assertContractVariable(
        L1ERC721Bridge,
        'messenger',
        L1CrossDomainMessenger.address
      )
    },
  })

  // Step 6 unpauses the PatexPortal.
  if (await isStep(SystemDictator, 6)) {
    console.log(`
      Unpause the PatexPortal. The GUARDIAN account should be used. In practice
      this is the multisig. In test networks, the PatexPortal is initialized
      without being paused.
    `)

    if (isLiveDeployer) {
      console.log('WARNING: PatexPortal configured to not be paused')
      console.log('This should only happen for test environments')
      await assertContractVariable(PatexPortal, 'paused', false)
    } else {
      const tx = await PatexPortal.populateTransaction.unpause()
      console.log(`Please unpause the PatexPortal...`)
      console.log(`PatexPortal address: ${PatexPortal.address}`)
      printJsonTransaction(tx)
      printCastCommand(tx)
      await printTenderlySimulationLink(SystemDictator.provider, tx)
    }

    await awaitCondition(
      async () => {
        const paused = await PatexPortal.paused()
        return !paused
      },
      5000,
      1000
    )

    await assertContractVariable(PatexPortal, 'paused', false)

    console.log(`
      You must now finalize the upgrade by calling finalize() on the SystemDictator. This will
      transfer ownership of the ProxyAdmin to the final system owner as specified in the deployment
      configuration.
    `)

    if (isLiveDeployer) {
      console.log(`Finalizing deployment...`)
      await SystemDictator.finalize()
    } else {
      const tx = await SystemDictator.populateTransaction.finalize()
      console.log(`Please finalize deployment...`)
      console.log(`MSD address: ${SystemDictator.address}`)
      printJsonTransaction(tx)
      printCastCommand(tx)
      await printTenderlySimulationLink(SystemDictator.provider, tx)
    }

    await awaitCondition(
      async () => {
        return SystemDictator.finalized()
      },
      5000,
      1000
    )

    await assertContractVariable(
      ProxyAdmin,
      'owner',
      hre.deployConfig.finalSystemOwner
    )
  }
}

deployFn.tags = ['SystemDictatorSteps', 'phase2', 'l1']

export default deployFn
