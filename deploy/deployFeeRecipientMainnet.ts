import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const feeRegistryAddress = '0x512fB27961D8204A94151bC03d5722FeBdc527c2'; // Mainnet

    await deployContract('feeRecipient', 'SyncSwapFeeRecipient',
        [feeRegistryAddress]
    );
}