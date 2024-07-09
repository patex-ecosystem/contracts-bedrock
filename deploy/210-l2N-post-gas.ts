
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const address = (await deployments.get('Lib_Postdeploys')).address;
    const gas = (await deployments.get('GasProxy')).address;
    const postdeploys = await ethers.getContractAt('Postdeploys', address);

    await postdeploys.setGAS(gas);

    console.log('Postdeploys', address);
    console.log('patex', gas);
}

deployFn.tags = ['l2PostGas']

export default deployFn

