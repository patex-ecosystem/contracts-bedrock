
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const address = (await deployments.get('Lib_Postdeploys')).address;
    const bridge = (await deployments.get('L2PatexBridgeProxy')).address;
    const postdeploys = await ethers.getContractAt('Postdeploys', address);

    await postdeploys.setL2_PATEX_BRIDGE(bridge);

    console.log('Postdeploys', address);
    console.log('patex', bridge);
}

deployFn.tags = ['l2PostBridge']

export default deployFn

