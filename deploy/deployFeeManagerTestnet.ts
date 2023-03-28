import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const feeRecipientAddress = '0x98f25D9E5473f258106FAA90C5a3993Ca81d61Bd'; // Testnet

    await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipientAddress]
    );
}