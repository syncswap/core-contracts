import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const feeRegistryAddress = '0x82Ec84c7368bb9089E1077c6e1703675c35A4237'; // Testnet

    await deployContract('feeRecipient', 'SyncSwapFeeRecipient',
        [feeRegistryAddress]
    );
}