import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const feeRecipientAddress = '0x432bcc3BC62DE9186f9E8763C82d43e418681e6C'; // Mainnet

    await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipientAddress]
    );
}