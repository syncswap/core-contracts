import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeWalletAndDeployer } from "../deploy-utils/helper";
import { ZERO_ADDRESS } from "../test/shared/utilities";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeWalletAndDeployer(hre);

    const wETHAddress: string = '0x20b28B1e4665FFf290650586ad76E977EAb90c5D';
    //const feeRecipientAddress: string = createArgument(ArgumentTypes.ACCOUNT);

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

    // 5. Fee Manager
    const feeManager = await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRegistry.address]
    );

    console.log('Initializing fee manager to master...');
    await master.setFeeManager(feeManager.address);
    console.log('Initialized fee manager to master.');

    // 6. Classic Pool Factory
    const classicFactory = await deployContract('classicPoolFactory', 'SyncSwapClassicPoolFactory',
        [master.address],
    );

    console.log('Whitelisting classic factory...');
    await master.setFactoryWhitelisted(classicFactory.address, true);
    console.log('Whitelisted classic factory.');

    // 7. Stable Pool Factory
    const stableFactory = await deployContract('stablePoolFactory', 'SyncSwapStablePoolFactory',
        [master.address],
    );

    console.log('Whitelisting stable factory...');
    await master.setFactoryWhitelisted(stableFactory.address, true);
    console.log('Whitelisted stable factory.');

    // 8. Router
    const router = await deployContract('router', 'SyncSwapRouter',
        [vault.address, wETHAddress],
    );

    console.log('Adding router as forwarder...');
    await forwarderRegistry.addForwarder(router.address);
    console.log('Added router as forwarder.');
}