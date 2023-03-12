import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ArgumentTypes, createArgument, deployContract, initializeWalletAndDeployer } from "../deploy-utils/helper";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeWalletAndDeployer(hre);

    const wETHAddress: string = '0x20b28B1e4665FFf290650586ad76E977EAb90c5D';
    const feeRecipientAddress: string = createArgument(ArgumentTypes.ACCOUNT);

    // Vault
    const vault = await deployContract('vault', 'SyncSwapVault',
        [wETHAddress],
    );

    // Forwarder Registry
    const forwarderRegistry = await deployContract('forwarderRegistry', 'ForwarderRegistry',
        []
    );

    // Fee Manager
    const feeManager = await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipientAddress]
    );

    // Pool Master
    const master = await deployContract('master', 'SyncSwapPoolMaster',
        [vault.address, forwarderRegistry.address, feeManager.address],
    );

    // Classic Pool Factory
    const classicFactory = await deployContract('classicPoolFactory', 'SyncSwapClassicPoolFactory',
        [master.address],
    );

    console.log('Whitelisting classic factory...');
    await master.setFactoryWhitelisted(classicFactory.address, true);
    console.log('Whitelisted classic factory.');

    // Stable Pool Factory
    const stableFactory = await deployContract('stablePoolFactory', 'SyncSwapStablePoolFactory',
        [master.address],
    );

    console.log('Whitelisting stable factory...');
    await master.setFactoryWhitelisted(stableFactory.address, true);
    console.log('Whitelisted stable factory.');

    // Router
    const router = await deployContract('router', 'SyncSwapRouter',
        [vault.address, wETHAddress],
    );

    console.log('Adding router as forwarder...');
    await forwarderRegistry.addForwarder(router.address);
    console.log('Added router as forwarder.');
}