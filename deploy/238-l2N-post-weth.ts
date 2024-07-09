
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const address = (await deployments.get('Lib_Postdeploys')).address;
    const weth = (await deployments.get('WETHRebasingProxy')).address;
    const postdeploys = await ethers.getContractAt('Postdeploys', address);

    await postdeploys.setWETH_REBASING(weth);

    console.log('Postdeploys', address);
    console.log('patex', weth);
}

deployFn.tags = ['l2PostWeth']

export default deployFn

