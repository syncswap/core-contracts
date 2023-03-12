import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ArgumentTypes, createArgument, deployContract, initializeWalletAndDeployer } from "../deploy-utils/helper";
import { BigNumber } from "ethers";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeWalletAndDeployer(hre);

    await deployContract('dtt', 'DeflatingERC20',
        [BigNumber.from(10).pow(18 + 11)], // 10b
    );
}