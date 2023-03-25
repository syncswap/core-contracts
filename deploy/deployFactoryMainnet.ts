import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const wETHAddress: string = '0x5aea5775959fbc2557cc8789bc1bf90a239d9a91'; // zkSync Mainnet WETH

    const vaultAddress = '0x621425a1Ef6abE91058E9712575dcc4258F8d091'; // zkSync Mainnet Vault
    const forwarderRegistryAddress = '0xF09B5EB4aa68Af47a8522155f8F73E93FB91F9d2'; // zkSync Mainnet Forwarder Registry
    const poolMasterAddress = '0xbB05918E9B4bA9Fe2c8384d223f0844867909Ffb';

    const classicFactory = await deployContract('classicPoolFactory', 'SyncSwapClassicPoolFactory',
        [poolMasterAddress],
    );

    const stableFactory = await deployContract('stablePoolFactory', 'SyncSwapStablePoolFactory',
        [poolMasterAddress],
    );

    const router = await deployContract('router', 'SyncSwapRouter',
        [vaultAddress, wETHAddress],
    );
}