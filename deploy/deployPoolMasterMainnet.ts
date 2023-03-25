import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";
import { ZERO_ADDRESS } from "../test/shared/utilities";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const vaultAddress = '0x621425a1Ef6abE91058E9712575dcc4258F8d091'; // zkSync Mainnet Vault
    const forwarderRegistryAddress = '0xF09B5EB4aa68Af47a8522155f8F73E93FB91F9d2'; // zkSync Mainnet Forwarder Registry

    await deployContract('master', 'SyncSwapPoolMaster',
        [vaultAddress, forwarderRegistryAddress, ZERO_ADDRESS],
    );
}