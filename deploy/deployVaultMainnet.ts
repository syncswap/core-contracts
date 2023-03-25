import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const wETHAddress: string = '0x5aea5775959fbc2557cc8789bc1bf90a239d9a91'; // zkSync Mainnet WETH

    await deployContract('vault', 'SyncSwapVault',
        [wETHAddress],
    );
}