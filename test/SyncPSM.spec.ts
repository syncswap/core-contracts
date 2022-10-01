import chai, { expect } from 'chai'
import { solidity } from 'ethereum-waffle'

import { deployContract, deployERC20, expandTo18Decimals, expandToDecimals, getAccount } from './utils/helper'
import { Constants } from './utils/constants'
import { Fixtures } from './utils/fixtures'
import { BigNumber } from 'ethers'

chai.use(solidity)

describe('SyncPSM', () => {

    // Fixtures are shared among tasks in this test.
    before(async () => {
        // Deploy PSM
        Fixtures.set('PSM', await deployContract('SyncPSM'));

        // Create stables
        const initialSupply = 1_000_000;
        Fixtures.set('USDC', await deployERC20('USD Coin', 'USDC', 6, expandToDecimals(initialSupply, 6))); // 6 decimals for USDC
        Fixtures.set('BUSD', await deployERC20('Binance USD', 'BUSD', 18, expandTo18Decimals(initialSupply)));
        Fixtures.set('DAI', await deployERC20('Dai', 'DAI', 18, expandTo18Decimals(initialSupply)));
        Fixtures.set('UST', await deployERC20('TerraUSD', 'UST', 18, expandTo18Decimals(initialSupply))); // shh
    });

    it('Should add assets to PSM', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');

        await expect(PSM.addAsset(Constants.ZERO_ADDRESS)).to.be.revertedWith('Invalid asset');
        await expect(PSM.addAsset((await getAccount(1)).address)).to.be.reverted; // Without reason

        await PSM.addAsset(USDC.address);
        await PSM.addAsset(BUSD.address);
        await PSM.addAsset(DAI.address);
        await PSM.addAsset(UST.address);

        await expect(await PSM.listedAssetsLength()).to.be.eq(4);
        await expect(await PSM.getListedAssets()).to.be.eql([USDC.address, BUSD.address, DAI.address, UST.address]);
    });

    it('Should remove UST from PSM', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');

        await PSM.removeAsset(UST.address);

        await expect(await PSM.listedAssetsLength()).to.be.eq(3);
        await expect(await PSM.getListedAssets()).to.be.eql([USDC.address, BUSD.address, DAI.address]);
    });

    it('Should set caps for assets', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');

        await expect(PSM.setCap(USDC.address, 0)).to.be.revertedWith('No changes made');

        await PSM.setCap(USDC.address, expandToDecimals(2_000_000, 6)); // 6 decimals for USDC
        await PSM.setCap(BUSD.address, expandTo18Decimals(100_000));
        await PSM.setCap(DAI.address, expandTo18Decimals(50_000));

        await expect(PSM.setCap(DAI.address, expandTo18Decimals(50_000))).to.be.revertedWith('No changes made');
        await expect(PSM.setCap(UST.address, 1)).to.be.revertedWith('Asset is not listed');

        await expect(await PSM.getCap(USDC.address)).to.be.eq(expandToDecimals(2_000_000, 6)); // 6 decimals for USDC
        await expect(await PSM.getCap(BUSD.address)).to.be.eq(expandTo18Decimals(100_000));
        await expect(await PSM.getCap(DAI.address)).to.be.eq(expandTo18Decimals(50_000));
        await expect(await PSM.getCap(UST.address)).to.be.eq(0);
    });

    it('Should approve assets for PSM', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');

        const unlimitedApprove = BigNumber.from(2).pow(256).sub(1);
        await USDC.approve(PSM.address, unlimitedApprove);
        await BUSD.approve(PSM.address, unlimitedApprove);
        await DAI.approve(PSM.address, unlimitedApprove);
        await UST.approve(PSM.address, unlimitedApprove);
    });

    it('Should deposit some assets', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');
        const accountAddress = (await getAccount(0)).address;

        // Invalid amount
        await expect(PSM.deposit(USDC.address, 0, accountAddress)).to.be.revertedWith('Amount must greater than zero');

        // Exceeds cap
        await expect(PSM.deposit(BUSD.address, expandTo18Decimals(100_001), accountAddress)).to.be.revertedWith('EXCEEDS_CAP');
        await expect(PSM.deposit(UST.address, 1, accountAddress)).to.be.revertedWith('EXCEEDS_CAP'); // Cap is 0 for not listed asset

        // Exceeds balance
        await expect(PSM.deposit(USDC.address, expandToDecimals(1_000_001, 6), accountAddress)).to.be.revertedWith('TransferHelper::transferFrom: transferFrom failed'); // 6 decimals for USDC

        await PSM.deposit(USDC.address, expandToDecimals(200_000, 6), accountAddress);
        await PSM.deposit(BUSD.address, expandTo18Decimals(100_000), accountAddress); // The same amount with cap
        await PSM.deposit(DAI.address, expandTo18Decimals(20_000), accountAddress);

        // Expect balances are subtracted
        await expect(await USDC.balanceOf(accountAddress)).to.be.eq(expandToDecimals(800_000, 6)); // 6 decimals for USDC
        await expect(await BUSD.balanceOf(accountAddress)).to.be.eq(expandTo18Decimals(900_000));
        await expect(await DAI.balanceOf(accountAddress)).to.be.eq(expandTo18Decimals(980_000));

        // Expect reserves to be equal with deposit amounts
        await expect(await PSM.getReserve(USDC.address)).to.be.eq(expandToDecimals(200_000, 6)); // 6 decimals for USDC
        await expect(await PSM.getReserve(BUSD.address)).to.be.eq(expandTo18Decimals(100_000));
        await expect(await PSM.getReserve(DAI.address)).to.be.eq(expandTo18Decimals(20_000));
        await expect(await PSM.getReserve(UST.address)).to.be.eq(0);

        // Expect user supply are credited
        await expect(await PSM.userSupplies(accountAddress, USDC.address)).to.be.eq(expandToDecimals(200_000, 6)); // 6 decimals for USDC
        await expect(await PSM.userSupplies(accountAddress, BUSD.address)).to.be.eq(expandTo18Decimals(100_000));
        await expect(await PSM.userSupplies(accountAddress, DAI.address)).to.be.eq(expandTo18Decimals(20_000));
    });

    it('Should withdraw some assets', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');
        const accountAddress = (await getAccount(0)).address;

        // Invalid amount
        await expect(PSM.withdraw(USDC.address, 0, accountAddress)).to.be.revertedWith('Amount must greater than zero');

        // Exceeds deposit
        await expect(PSM.withdraw(USDC.address, expandToDecimals(200_001, 6), accountAddress)).to.be.reverted;
        await expect(PSM.withdraw(UST.address, 1, accountAddress)).to.be.reverted;

        await PSM.withdraw(USDC.address, expandTo18Decimals(100_000), accountAddress); // Withdraw are using native decimals
        await PSM.withdraw(BUSD.address, expandTo18Decimals(50_000), accountAddress);
        await PSM.withdraw(DAI.address, expandTo18Decimals(20_000), accountAddress); // Withdraw all deposit

        // Expect balances are changed
        await expect(await USDC.balanceOf(accountAddress)).to.be.eq(expandToDecimals(900_000, 6)); // 6 decimals for USDC
        await expect(await BUSD.balanceOf(accountAddress)).to.be.eq(expandTo18Decimals(950_000));
        await expect(await DAI.balanceOf(accountAddress)).to.be.eq(expandTo18Decimals(1_000_000));

        // Expect reserves are subtracted
        await expect(await PSM.getReserve(USDC.address)).to.be.eq(expandToDecimals(100_000, 6)); // 6 decimals for USDC
        await expect(await PSM.getReserve(BUSD.address)).to.be.eq(expandTo18Decimals(50_000));
        await expect(await PSM.getReserve(DAI.address)).to.be.eq(0);

        // Expect user supply has been spent
        await expect(await PSM.userSupplies(accountAddress, USDC.address)).to.be.eq(expandToDecimals(100_000, 6)); // 6 decimals for USDC
        await expect(await PSM.userSupplies(accountAddress, BUSD.address)).to.be.eq(expandTo18Decimals(50_000));
        await expect(await PSM.userSupplies(accountAddress, DAI.address)).to.be.eq(0);
    });

    it('Should swap some assets', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const UST = Fixtures.use('UST');
        const accountAddress = (await getAccount(0)).address;

        // Identical assets
        await expect(PSM.swap(USDC.address, USDC.address, 100, accountAddress)).to.be.revertedWith('Identical assets');

        // Invalid amount
        await expect(PSM.swap(USDC.address, BUSD.address, 0, accountAddress)).to.be.revertedWith('Amount must greater than zero');

        // Exceeds cap
        await expect(PSM.swap(DAI.address, USDC.address, expandTo18Decimals(50_001), accountAddress)).to.be.revertedWith('EXCEEDS_CAP');
        await expect(PSM.swap(UST.address, USDC.address, 1, accountAddress)).to.be.revertedWith('EXCEEDS_CAP');

        // Exceeds balance
        await expect(PSM.swap(USDC.address, BUSD.address, expandToDecimals(900_001, 6), accountAddress)).to.be.revertedWith('TransferHelper::transferFrom: transferFrom failed'); // 6 decimals for USDC

        // Exceeds reserve of output asset
        await expect(PSM.swap(USDC.address, BUSD.address, expandToDecimals(50_001, 6), accountAddress)).to.be.reverted; // 6 decimals for USDC

        await expect(PSM.swap(BUSD.address, USDC.address, expandTo18Decimals(10_000), accountAddress))
            .to.emit(PSM, 'Swap')
            .withArgs(accountAddress, BUSD.address, USDC.address, expandTo18Decimals(10_000), expandToDecimals(9_995, 6), accountAddress);

        await expect(PSM.swap(DAI.address, USDC.address, expandTo18Decimals(10_000), accountAddress))
            .to.emit(PSM, 'Swap')
            .withArgs(accountAddress, DAI.address, USDC.address, expandTo18Decimals(10_000), expandToDecimals(9_995, 6), accountAddress);

        await expect(PSM.swap(USDC.address, BUSD.address, expandToDecimals(10_000, 6), accountAddress))
            .to.emit(PSM, 'Swap')
            .withArgs(accountAddress, USDC.address, BUSD.address, expandToDecimals(10_000, 6), expandTo18Decimals(9_995), accountAddress);

        await expect(PSM.swap(BUSD.address, DAI.address, expandTo18Decimals(10_000), accountAddress))
            .to.emit(PSM, 'Swap')
            .withArgs(accountAddress, BUSD.address, DAI.address, expandTo18Decimals(10_000), expandTo18Decimals(9_995), accountAddress);

        // Expect balances are changed
        await expect(await USDC.balanceOf(accountAddress)).to.be.eq(expandToDecimals(909_990, 6)); // 6 decimals for USDC
        await expect(await BUSD.balanceOf(accountAddress)).to.be.eq(expandTo18Decimals(939_995));
        await expect(await DAI.balanceOf(accountAddress)).to.be.eq(expandTo18Decimals(999_995));

        // Expect reserves are changed
        await expect(await PSM.getReserve(USDC.address)).to.be.eq(expandToDecimals(90_000, 6)); // 6 decimals for USDC
        await expect(await PSM.getReserve(BUSD.address)).to.be.eq(expandTo18Decimals(60_000));
        await expect(await PSM.getReserve(DAI.address)).to.be.eq(0);

        // Expect user supply has no changes (for swaps)
        await expect(await PSM.userSupplies(accountAddress, USDC.address)).to.be.eq(expandToDecimals(100_000, 6)); // 6 decimals for USDC
        await expect(await PSM.userSupplies(accountAddress, BUSD.address)).to.be.eq(expandTo18Decimals(50_000));
        await expect(await PSM.userSupplies(accountAddress, DAI.address)).to.be.eq(0);
    });

    it('Should returns expected amount and fee', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const accountAddress = (await getAccount(0)).address;

        // USDC user supply is 100k
        await expect(await PSM.getWithdrawFee(accountAddress, USDC.address, expandToDecimals(100_000, 6))).to.be.eq(0);
        await expect(await PSM.getWithdrawOut(accountAddress, USDC.address, expandToDecimals(100_000, 6))).to.be.eq(expandToDecimals(100_000, 6));

        await expect(await PSM.getWithdrawFee(accountAddress, USDC.address, expandToDecimals(200_000, 6))).to.be.eq(expandToDecimals(50, 6));
        await expect(await PSM.getWithdrawOut(accountAddress, USDC.address, expandToDecimals(200_000, 6))).to.be.eq(expandToDecimals(199_950, 6));

        // BUSD user supply is 50k
        await expect(await PSM.getWithdrawFee(accountAddress, BUSD.address, expandTo18Decimals(50_000))).to.be.eq(0);
        await expect(await PSM.getWithdrawOut(accountAddress, BUSD.address, expandTo18Decimals(50_000))).to.be.eq(expandTo18Decimals(50_000));

        await expect(await PSM.getWithdrawFee(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(5));
        await expect(await PSM.getWithdrawOut(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(59_995));

        // DAI user supply is 0
        await expect(await PSM.getWithdrawFee(accountAddress, DAI.address, expandTo18Decimals(10_000))).to.be.eq(expandTo18Decimals(5));
        await expect(await PSM.getWithdrawOut(accountAddress, DAI.address, expandTo18Decimals(10_000))).to.be.eq(expandTo18Decimals(9_995));

        // Swaps always impose the full fee
        await expect(await PSM.getSwapFee(expandTo18Decimals(10_000))).to.be.eq(expandTo18Decimals(5));

        await expect(await PSM.getSwapOut(USDC.address, DAI.address, expandToDecimals(10_000, 6))).to.be.eq(expandTo18Decimals(9_995)); // 6 -> 18 decimals
        await expect(await PSM.getSwapOut(DAI.address, USDC.address, expandTo18Decimals(10_000))).to.be.eq(expandToDecimals(9_995, 6)); // 18 -> 6 decimals
        await expect(await PSM.getSwapOut(BUSD.address, DAI.address, expandTo18Decimals(10_000))).to.be.eq(expandTo18Decimals(9_995)); // 18 -> 18 decimals
    });

    it('Should rescue stucked tokens', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const UST = Fixtures.use('UST');
        const accountAddress = (await getAccount(0)).address;

        // Token that is listed
        await expect(await PSM.rescuableERC20(USDC.address)).to.be.eq(0);
        await USDC.transfer(PSM.address, expandToDecimals(100, 6));
        await expect(await PSM.rescuableERC20(USDC.address)).to.be.eq(expandToDecimals(100, 6));

        await expect(PSM.rescueERC20(USDC.address))
            .to.emit(USDC, 'Transfer')
            .withArgs(PSM.address, accountAddress, expandToDecimals(100, 6));

        // Token that not listed
        await expect(await PSM.rescuableERC20(UST.address)).to.be.eq(0);
        await UST.transfer(PSM.address, expandTo18Decimals(100));
        await expect(await PSM.rescuableERC20(UST.address)).to.be.eq(expandTo18Decimals(100));

        await expect(PSM.rescueERC20(UST.address))
            .to.emit(UST, 'Transfer')
            .withArgs(PSM.address, accountAddress, expandTo18Decimals(100));
    });

    it('Should pause deposit and swap', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const DAI = Fixtures.use('DAI');
        const accountAddress = (await getAccount(0)).address;

        // Pause deposit
        await PSM.setDepositPaused(true);
        await expect(PSM.deposit(USDC.address, 1, accountAddress)).to.be.revertedWith('Deposit is paused');
        await PSM.setDepositPaused(false);

        // Pause swap
        await PSM.setSwapPaused(true);
        await expect(PSM.swap(USDC.address, DAI.address, 1, accountAddress)).to.be.revertedWith('Swap is paused');
        await PSM.setSwapPaused(false);
    });

    it('Should transfer accrued fees', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const feeRecipientAddress = (await getAccount(1)).address;

        await expect(await PSM.accruedFees(USDC.address)).to.be.eq(expandToDecimals(10, 6));
        await expect(await PSM.accruedFees(BUSD.address)).to.be.eq(expandTo18Decimals(5));
        await expect(await PSM.accruedFees(DAI.address)).to.be.eq(expandTo18Decimals(5));

        await expect(PSM.transferAccruedFeeFor(USDC.address)).to.be.revertedWith('No fee recipient');
        await PSM.setSwapFeeRecipient(feeRecipientAddress);

        await expect(PSM.transferAccruedFeeFor(USDC.address))
            .to.emit(USDC, 'Transfer')
            .withArgs(PSM.address, feeRecipientAddress, expandToDecimals(10, 6));

        await expect(PSM.transferAllAccruedFees())
            .to.emit(BUSD, 'Transfer')
            .withArgs(PSM.address, feeRecipientAddress, expandTo18Decimals(5))
            .to.emit(DAI, 'Transfer')
            .withArgs(PSM.address, feeRecipientAddress, expandTo18Decimals(5));
        
        // Expect fees are subtracted
        await expect(await PSM.accruedFees(USDC.address)).to.be.eq(0);
        await expect(await PSM.accruedFees(BUSD.address)).to.be.eq(0);
        await expect(await PSM.accruedFees(DAI.address)).to.be.eq(0);
    });

    it('Should change fee rate', async () => {
        const PSM = Fixtures.use('PSM');
        const BUSD = Fixtures.use('BUSD');
        const DAI = Fixtures.use('DAI');
        const accountAddress = (await getAccount(0)).address;

        await expect(await PSM.swapFee()).to.be.eq(50_000); // 0.05% as 1e8 precision
        // BUSD user supply is 50k
        await expect(await PSM.getWithdrawFee(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(5));
        await expect(await PSM.getWithdrawOut(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(59_995));

        await PSM.setSwapFee(0);
        await expect(await PSM.getWithdrawFee(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(0);
        await expect(await PSM.getWithdrawOut(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(60_000));

        await PSM.setSwapFee(10_000); // 0.01%
        await expect(await PSM.getWithdrawFee(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(1));
        await expect(await PSM.getWithdrawOut(accountAddress, BUSD.address, expandTo18Decimals(60_000))).to.be.eq(expandTo18Decimals(59_999));

        // Perform an actual swap
        await expect(PSM.swap(DAI.address, BUSD.address, expandTo18Decimals(10_000), accountAddress))
            .to.emit(PSM, 'Swap')
            .withArgs(accountAddress, DAI.address, BUSD.address, expandTo18Decimals(10_000), expandTo18Decimals(9_999), accountAddress);
        
        await expect(await PSM.accruedFees(BUSD.address)).to.be.eq(expandTo18Decimals(1));
    });

    it('Should emergency withdraw', async () => {
        const PSM = Fixtures.use('PSM');
        const USDC = Fixtures.use('USDC');
        const accountAddress = (await getAccount(0)).address;

        await expect(PSM.emergencyWithdraw(USDC.address, expandToDecimals(10_000, 6))).to.be.revertedWith('Emergency withdraw is not enabled');

        await PSM.setEmergencyWithdrawEnabled(true);

        await expect(PSM.emergencyWithdraw(USDC.address, 0)).to.be.revertedWith('Amount must greater than zero');
        await expect(PSM.emergencyWithdraw(USDC.address, expandTo18Decimals(10_000)))
            .to.emit(PSM, 'Withdraw')
            .withArgs(accountAddress, USDC.address, expandTo18Decimals(10_000), expandToDecimals(10_000, 6), accountAddress)
            .to.emit(PSM, 'Transfer')
            .withArgs(accountAddress, Constants.ZERO_ADDRESS, expandTo18Decimals(10_000))
            .to.emit(USDC, 'Transfer')
            .withArgs(PSM.address, accountAddress, expandToDecimals(10_000, 6));

        await expect(await PSM.userSupplies(accountAddress, USDC.address)).to.be.eq(0);
        await expect(await PSM.getReserve(USDC.address)).to.be.eq(expandToDecimals(90_000, 6));
    });

    it('Should mint and burn some tokens', async () => {
        const PSM = Fixtures.use('PSM');
        const account = await getAccount(0);
        const minter1 = await getAccount(2);
        const minter2 = await getAccount(3);

        await expect(PSM.setMinterCap(minter1.address, 1)).to.be.revertedWith('Not a minter');
        await expect(PSM.mint(minter1.address, 0)).to.be.revertedWith('Invalid amount to mint');
        await expect(PSM.mint(minter1.address, 1)).to.be.revertedWith('EXCEEDS_CAP');
        await expect(PSM.burn(0)).to.be.revertedWith('Invalid amount to burn');
        await expect(PSM.burn(1)).to.be.revertedWith('Not a minter');

        await expect(PSM.addMinter(Constants.ZERO_ADDRESS)).to.be.revertedWith('Invalid minter');
        await PSM.addMinter(minter1.address);
        await expect(PSM.addMinter(minter1.address)).to.be.revertedWith('Minter already exists');

        await PSM.addMinter(minter2.address);
        await expect(await PSM.mintersLength()).to.be.eq(2);
        await expect(await PSM.getMinters()).to.be.eql([minter1.address, minter2.address]);

        await PSM.setMinterCap(minter1.address, expandTo18Decimals(1000));
        await expect(PSM.setMinterCap(minter1.address, expandTo18Decimals(1000))).to.be.revertedWith('No changes made');

        await expect(PSM.connect(minter1).mint(minter1.address, expandTo18Decimals(1001))).to.be.revertedWith('EXCEEDS_CAP');
        await expect(PSM.connect(minter1).mint(minter1.address, expandTo18Decimals(1000)))
            .to.emit(PSM, 'Transfer')
            .withArgs(Constants.ZERO_ADDRESS, minter1.address, expandTo18Decimals(1000));
        
        await PSM.connect(account).setMinterCap(minter2.address, expandTo18Decimals(1000));
        await PSM.removeMinter(minter2.address);
        await expect(PSM.removeMinter(minter1.address)).to.be.revertedWith('Cannot remove minter with supply');

        await expect(PSM.connect(minter1).burn(expandTo18Decimals(1000)))
            .to.emit(PSM, 'Transfer')
            .withArgs(minter1.address, Constants.ZERO_ADDRESS, expandTo18Decimals(1000));
        await PSM.removeMinter(minter1.address);
    });
});