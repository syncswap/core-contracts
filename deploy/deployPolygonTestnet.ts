import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "hardhat";
import { ZERO_ADDRESS } from "../test/shared/utilities";
import { deployContractEth } from "../deploy-utils/helper";

async function main() {
    const wETHAddress: string = '0xee589e91401066068af129b0005ac3ef69e3fdb4'; // Polygon zkEVM Testnet WETH

    // 1. Vault
    const vault = await deployContractEth('vault', 'SyncSwapVault',
        [wETHAddress],
    );

    // 2. Forwarder Registry
    const forwarderRegistry = await deployContractEth('forwarderRegistry', 'ForwarderRegistry',
        []
    );

    // 3. Pool Master
    const master = await deployContractEth('master', 'SyncSwapPoolMaster',
        [vault.address, forwarderRegistry.address, ZERO_ADDRESS],
    );

    // 4. Fee Registry
    const feeRegistry = await deployContractEth('feeRegistry', 'FeeRegistry',
        [master.address]
    );

    console.log('Adding vault as fee sender...');
    await feeRegistry.setSenderWhitelisted(vault.address, true);
    console.log('Added vault as fee sender.');

    // 5. Fee Recipient
    const feeRecipient = await deployContractEth('feeRecipient', 'SyncSwapFeeRecipient',
        [feeRegistry.address]
    );

    // 6. Fee Manager
    const feeManager = await deployContractEth('feeManager', 'SyncSwapFeeManager',
        [feeRecipient.address]
    );

    console.log('Initializing fee manager to master...');
    await master.setFeeManager(feeManager.address);
    console.log('Initialized fee manager to master.');

    // 7. Classic Pool Factory
    const classicFactory = await deployContractEth('classicPoolFactory', 'SyncSwapClassicPoolFactory',
        [master.address],
    );

    console.log('Whitelisting classic factory...');
    await master.setFactoryWhitelisted(classicFactory.address, true);
    console.log('Whitelisted classic factory.');

    // 8. Stable Pool Factory
    const stableFactory = await deployContractEth('stablePoolFactory', 'SyncSwapStablePoolFactory',
        [master.address],
    );

    console.log('Whitelisting stable factory...');
    await master.setFactoryWhitelisted(stableFactory.address, true);
    console.log('Whitelisted stable factory.');

    // 9. Router
    const router = await deployContractEth('router', 'SyncSwapRouter',
        [vault.address, wETHAddress],
    );

    console.log('Adding router as forwarder...');
    await forwarderRegistry.addForwarder(router.address);
    console.log('Added router as forwarder.');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});