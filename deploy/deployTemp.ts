import { HardhatRuntimeEnvironment } from "hardhat/types";
import { deployContract, initializeZkSyncWalletAndDeployer } from "../deploy-utils/helper";
import { ZERO_ADDRESS } from "../test/shared/utilities";

export default async function (hre: HardhatRuntimeEnvironment) {
    initializeZkSyncWalletAndDeployer(hre);

    const wETHAddress: string = '0x20b28B1e4665FFf290650586ad76E977EAb90c5D';
    //const feeRecipientAddress: string = createArgument(ArgumentTypes.ACCOUNT);

    // 1. Vault
    const vaultAddress = '0x29B46ca1f2610019B01484d1aDf83a4f51bBCD9c'

    // 2. Forwarder Registry
    const forwarderRegistryAddress = '0xA878b73Fb0fd1863D8EE5d2d30120E3F5a548993'

    // 3. Pool Master
    const masterAddress = '0x716a8c2d07288EEeEf2151efC67a9b62F808b34a'

    // 4. Fee Registry
    const feeRegistryAddress = '0xCd89A32562df49A09B05f30F727B855BFC42661e'

    // 5. Fee Recipient
    const feeRecipientAddress = '0x7C14dd69165B786D7040446A43088bD122505f83'

    // Done
    //console.log('Adding vault as fee sender...');
    //await feeRegistry.setSenderWhitelisted(vaultAddress, true);
    //console.log('Added vault as fee sender.');

    // 6. Fee Manager
    const feeManager = await deployContract('feeManager', 'SyncSwapFeeManager',
        [feeRecipientAddress]
    );

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