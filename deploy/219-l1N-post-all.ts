
import { DeployFunction } from 'hardhat-deploy/dist/types'

const { ethers, deployments, getNamedAccounts } = require('hardhat');

import {
  deploy,
} from '../src/deploy-utils'

const deployFn: DeployFunction = async (hre) => {

    const { deployer } = await getNamedAccounts();
    const { execute } = deployments;

    const address = (await deployments.get('Lib_Postdeploys')).address;
    const postdeploys = await ethers.getContractAt('Postdeploys', address);

    const l2bridge = "0x35FbeAb87d6252802Fc325d6C6AE2e6e758dd76D"
    const l2gas = "0x17ca24570E9A78e1A3B72f81c61b13D08CE541cD"
    const l2shares = "0x0F2395DD2Dde5A0E905B35491Fe38873B65Bb16B"
    const l2patex = "0x2546E425567AC9fc9e698D76D973d8E1329A5b90"

    const tx = await postdeploys.setL2_PATEX_BRIDGE(l2bridge);
    await tx.wait(1)
    const tx1 = await postdeploys.setGAS(l2gas);
    await tx1.wait(1)
    const tx2 = await postdeploys.setSHARES(l2shares);
    await tx2.wait(1)
    const tx3 = await postdeploys.setPATEX(l2patex);
    await tx3.wait(1)

    console.log("l1PostAll success")
}

deployFn.tags = ['l1PostAll']

export default deployFn

