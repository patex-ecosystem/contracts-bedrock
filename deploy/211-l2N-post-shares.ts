
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const address = (await deployments.get('Lib_Postdeploys')).address;
    const shares = (await deployments.get('SharesProxy')).address;
    const postdeploys = await ethers.getContractAt('Postdeploys', address);

    await postdeploys.setSHARES(shares);

    console.log('Postdeploys', address);
    console.log('patex', shares);
}

deployFn.tags = ['l2PostShares']

export default deployFn

