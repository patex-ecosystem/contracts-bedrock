import { task, types } from 'hardhat/config'
import { NodeProvider } from '@eth-patex/core-utils'

// TODO(tynes): add in config validation
task('check-pt-node', 'Validate the config of the pt-node')
  .addParam(
    'opNodeUrl',
    'URL of the PATEX Node.',
    'http://localhost:7545',
    types.string
  )
  .setAction(async (args) => {
    const provider = new NodeProvider(args.opNodeUrl)

    const syncStatus = await provider.syncStatus()
    console.log(JSON.stringify(syncStatus, null, 2))

    const config = await provider.rollupConfig()
    console.log(JSON.stringify(config, null, 2))
  })
