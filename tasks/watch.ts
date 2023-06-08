import { task, types } from 'hardhat/config'
import '@nomiclabs/hardhat-ethers'
import 'hardhat-deploy'
import { NodeProvider, sleep } from '@eth-patex/core-utils'

import { predeploys } from '../src'

task('watch', 'Watch an Patex System')
  .addParam(
    'l1ProviderUrl',
    'L1 provider URL.',
    'http://localhost:8545',
    types.string
  )
  .addParam(
    'l2ProviderUrl',
    'L2 provider URL.',
    'http://localhost:9545',
    types.string
  )
  .addParam(
    'opNodeProviderUrl',
    'pt-node provider URL',
    'http://localhost:7545',
    types.string
  )
  .setAction(async (args, hre) => {
    const { utils } = hre.ethers

    const l1Provider = new hre.ethers.providers.StaticJsonRpcProvider(
      args.l1Provider
    )
    const l2Provider = new hre.ethers.providers.StaticJsonRpcProvider(
      args.l2ProviderUrl
    )

    const contracts = {}
    const deployments = await hre.deployments.all()
    for (const [contract, deployment] of Object.entries(deployments)) {
      contracts[contract] = deployment.address
    }
    console.log('Deployed Contracts')
    console.table(contracts)

    const nodeProvider = new NodeProvider(args.opNodeProviderUrl)
    const nodeConfig = await nodeProvider.rollupConfig()
    console.log('pt-node config')
    console.table({
      'layer-one-hash': nodeConfig.genesis.l1.hash,
      'layer-one-number': nodeConfig.genesis.l1.number,
      'layer-two-hash': nodeConfig.genesis.l2.hash,
      'layer-two-number': nodeConfig.genesis.l2.number,
      'layer-two-time': nodeConfig.genesis.l2_time,
      'block-time': nodeConfig.block_time,
      'max-sequencer-drift': nodeConfig.max_sequencer_drift,
      'seq-window-size': nodeConfig.seq_window_size,
      'channel-timeout': nodeConfig.channel_timeout,
      'l1-chain-id': nodeConfig.l1_chain_id,
      'l2-chain-id': nodeConfig.l2_chain_id,
      'p2p-sequencer-address': nodeConfig.p2p_sequencer_address,
      'fee-recipient-address': nodeConfig.fee_recipient_address,
      'batch-inbox-address': nodeConfig.batch_inbox_address,
      'batch-sender-address': nodeConfig.batch_sender_address,
      'deposit-contract-address': nodeConfig.deposit_contract_address,
    })

    const Deployment__L2OutputOracle = await hre.deployments.get(
      'L2OutputOracle'
    )

    const Deployment__L2OutputOracleProxy = await hre.deployments.get(
      'L2OutputOracleProxy'
    )

    const L2OutputOracle = new hre.ethers.Contract(
      Deployment__L2OutputOracleProxy.address,
      Deployment__L2OutputOracle.abi,
      l1Provider
    )

    const proposer = await L2OutputOracle.proposer()
    console.log(`L2OutputOracle proposer ${proposer}`)
    console.log()

    setInterval(async () => {
      const latestBlockNumber = await L2OutputOracle.latestBlockNumber()
      console.log(
        `L2OutputOracle latest block number: ${latestBlockNumber.toString()}`
      )
      console.log()
    }, 10000)

    l1Provider.on('block', async (num) => {
      const block = await l1Provider.getBlockWithTransactions(num)
      for (const txn of block.transactions) {
        const to = utils.getAddress(txn.to || hre.ethers.constants.AddressZero)
        const from = utils.getAddress(txn.from)
        const isBatchSender =
          utils.getAddress(txn.from) ===
          utils.getAddress(nodeConfig.batch_sender_address)
        const isBatchInbox =
          to === utils.getAddress(nodeConfig.batch_inbox_address)

        const isOutputOracle =
          to === utils.getAddress(L2OutputOracle.address) &&
          from === utils.getAddress(proposer)

        if (isBatchSender && isBatchInbox) {
          console.log('Batch submitted:')
          console.log(`  tx hash: ${txn.hash}`)
          console.log(`  tx data: ${txn.data}`)
          console.log()
        }

        if (isOutputOracle) {
          console.log('L2 Output Submitted:')
          const data = L2OutputOracle.interface.parseTransaction(txn)
          console.log(`  tx hash: ${txn.hash}`)
          console.log(`    output root:   ${data.args._outputRoot}`)
          console.log(`    l2 blocknum:   ${data.args._l2BlockNumber}`)
          console.log(`    l1 blockhash:  ${data.args._l1Blockhash}`)
          console.log(`    l1 blocknum:   ${data.args._l1BlockNumber}`)
          console.log()
        }
      }
    })

    const L1Block = await hre.ethers.getContractAt(
      'L1Block',
      predeploys.L1Block
    )

    l2Provider.on('block', async (num) => {
      const block = await l2Provider.getBlockWithTransactions(num)
      for (const txn of block.transactions) {
        const to = utils.getAddress(txn.to || hre.ethers.constants.AddressZero)

        if (to === utils.getAddress(predeploys.L1Block)) {
          const data = L1Block.interface.parseTransaction(txn)
          console.log('L1Block values updated')
          console.log(`  tx hash: ${txn.hash}`)
          console.log(`    number:         ${data.args._number}`)
          console.log(`    timestamp:      ${data.args._timestamp}`)
          console.log(`    basefee:        ${data.args._basefee}`)
          console.log(`    hash:           ${data.args._hash}`)
          console.log(`    sequenceNumber: ${data.args._sequenceNumber}`)
          console.log()
        }
      }
    })

    setInterval(async () => {
      await sleep(100000)
    })
    await sleep(100000)
  })
