import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const vaultAddress = '0x621425a1Ef6abE91058E9712575dcc4258F8d091'; // zkSync Mainnet Vault
    const forwarderRegistryAddress = '0xF09B5EB4aa68Af47a8522155f8F73E93FB91F9d2'; // zkSync Mainnet Forwarder Registry
    const poolMasterAddress = '0xbB05918E9B4bA9Fe2c8384d223f0844867909Ffb';

    const feeRegistry = await deployContract('feeRegistry', 'FeeRegistry',
        [poolMasterAddress]
    );

    console.log('Adding vault as fee sender...');
    await feeRegistry.setSenderWhitelisted(vaultAddress, true);
    console.log('Added vault as fee sender.');

    // 5. Fee Recipient
    const feeRecipient = await deployContract('feeRecipient', 'SyncSwapFeeRecipient',
        [feeRegistry.address]
    );

    // 6. Fee Manager
    const feeManager = await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipient.address]
    );
}