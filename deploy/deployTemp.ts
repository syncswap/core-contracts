import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeWalletAndDeployer } from "../deploy-utils/helper";
import { ZERO_ADDRESS } from "../test/shared/utilities";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeWalletAndDeployer(hre);

    const wETHAddress: string = '0x20b28B1e4665FFf290650586ad76E977EAb90c5D';
    //const feeRecipientAddress: string = createArgument(ArgumentTypes.ACCOUNT);

    // 1. Vault
    const vaultAddress = '0x1b2966448791497D9fE66B2F46d0fD373Df42342'

    // 2. Forwarder Registry
    const forwarderRegistryAddress = '0x6f7312e0592E69CdFe5406BFdF8166b080Ab73Ad'

    // 3. Pool Master
    const masterAddress = '0x744A255b2625ccf253a7f3a5ef47D6942Dc9170a'

    // 4. Fee Registry
    const feeRegistryAddress = '0xFA86895dcCd79CB1530C74fDa04211Ac37b24dC3'

    // 5. Fee Recipient
    const feeRecipient = await deployContract('feeRecipient', 'SyncSwapFeeRecipient',
        [feeRegistryAddress]
    );

    // Done
    //console.log('Adding vault as fee sender...');
    //await feeRegistry.setSenderWhitelisted(vaultAddress, true);
    //console.log('Added vault as fee sender.');

    // 6. Fee Manager
    const feeManager = await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipient.address]
    );

    // Done
    //console.log('Initializing fee manager to master...');
    //await master.setFeeManager(feeManager.address);
    //console.log('Initialized fee manager to master.');

    // 7. Classic Pool Factory
    const classicFactory = await deployContract('classicPoolFactory', 'SyncSwapClassicPoolFactory',
        [masterAddress],
    );

    //console.log('Whitelisting classic factory...');
    //await master.setFactoryWhitelisted(classicFactory.address, true);
    //console.log('Whitelisted classic factory.');

    // 8. Stable Pool Factory
    const stableFactory = await deployContract('stablePoolFactory', 'SyncSwapStablePoolFactory',
        [masterAddress],
    );

    //console.log('Whitelisting stable factory...');
    //await master.setFactoryWhitelisted(stableFactory.address, true);
    //console.log('Whitelisted stable factory.');

    // 9. Router
    const router = await deployContract('router', 'SyncSwapRouter',
        [vaultAddress, wETHAddress],
    );

    //console.log('Adding router as forwarder...');
    //await forwarderRegistry.addForwarder(router.address);
    //console.log('Added router as forwarder.');
}