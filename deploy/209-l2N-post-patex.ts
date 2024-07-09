
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const address = (await deployments.get('Lib_Postdeploys')).address;
    const patex = (await deployments.get('PatexProxy')).address;
    const postdeploys = await ethers.getContractAt('Postdeploys', address);

    await postdeploys.setPATEX(patex);

    console.log('Postdeploys', address);
    console.log('patex', patex);
}

deployFn.tags = ['l2PostPatex']

export default deployFn

