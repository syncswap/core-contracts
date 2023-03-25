import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";
import { ZERO_ADDRESS } from "../test/shared/utilities";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const wETHAddress: string = '0x5aea5775959fbc2557cc8789bc1bf90a239d9a91'; // zkSync Mainnet WETH

    // 1. Vault
    const vault = await deployContract('vault', 'SyncSwapVault',
        [wETHAddress],
    );

    // 2. Forwarder Registry
    const forwarderRegistry = await deployContract('forwarderRegistry', 'ForwarderRegistry',
        []
    );

    // 3. Pool Master
    const master = await deployContract('master', 'SyncSwapPoolMaster',
        [vault.address, forwarderRegistry.address, ZERO_ADDRESS],
    );

    // 4. Fee Registry
    const feeRegistry = await deployContract('feeRegistry', 'FeeRegistry',
        [master.address]
    );

    console.log('Adding vault as fee sender...');
    await feeRegistry.setSenderWhitelisted(vault.address, true);
    console.log('Added vault as fee sender.');

    // 5. Fee Recipient
    const feeRecipient = await deployContract('feeRecipient', 'SyncSwapFeeRecipient',
        [feeRegistry.address]
    );

    // 6. Fee Manager
    const feeManager = await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipient.address]
    );

    console.log('Initializing fee manager to master...');
    await master.setFeeManager(feeManager.address);
    console.log('Initialized fee manager to master.');

    // 7. Classic Pool Factory
    const classicFactory = await deployContract('classicPoolFactory', 'SyncSwapClassicPoolFactory',
        [master.address],
    );

    console.log('Whitelisting classic factory...');
    await master.setFactoryWhitelisted(classicFactory.address, true);
    console.log('Whitelisted classic factory.');

    // 8. Stable Pool Factory
    const stableFactory = await deployContract('stablePoolFactory', 'SyncSwapStablePoolFactory',
        [master.address],
    );

    console.log('Whitelisting stable factory...');
    await master.setFactoryWhitelisted(stableFactory.address, true);
    console.log('Whitelisted stable factory.');

    // 9. Router
    const router = await deployContract('router', 'SyncSwapRouter',
        [vault.address, wETHAddress],
    );

    console.log('Adding router as forwarder...');
    await forwarderRegistry.addForwarder(router.address);
    console.log('Added router as forwarder.');
}