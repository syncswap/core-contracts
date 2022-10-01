import chai, { expect } from 'chai'
import { solidity } from 'ethereum-waffle'

import { createPair, deployERC20, deployFactory, deployFeeReceiver, encodePrice, expandTo18Decimals, getAccount, getAccounts, getPair, mineBlock, mineBlockAfter } from './utils/helper'
import { Constants } from './utils/constants'
import { Fixtures } from './utils/fixtures'
import { BigNumber, Contract } from 'ethers'

const hre = require("hardhat");
chai.use(solidity)

//const DISTRIBUTION_ACCOUNTS = [6, 7, 8];

describe('SyncSwapFeeReceiver', () => {

    beforeEach(async () => {
        const account = await getAccount(0);
        const factory = Fixtures.set('factory', await deployFactory(account.address));

        // Create tokens
        const commonBase = Fixtures.set('commonBase', await deployERC20('Common Base Token', 'CBT', 18, expandTo18Decimals(10000)));
        const commonBase2 = Fixtures.set('commonBase2', await deployERC20('Common Base Token2', 'CBT2', 18, expandTo18Decimals(10000)));
        const swapFor = Fixtures.set('swapFor', await deployERC20('Protocol Token', 'PT', 18, expandTo18Decimals(10000)));
        const other = Fixtures.set('other', await deployERC20('Other Token', 'OT', 18, expandTo18Decimals(10000)));
        const tokenA = Fixtures.set('tokenA', await deployERC20('Test Token A', 'TESTA', 18, expandTo18Decimals(10000)));
        const tokenB = Fixtures.set('tokenB', await deployERC20('Test Token B', 'TESTB', 18, expandTo18Decimals(10000)));
        const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];
        Fixtures.set('token0', token0);
        Fixtures.set('token1', token1);

        // Set fee receiver
        const feeReceiver = Fixtures.set('feeReceiver', await deployFeeReceiver(factory.address, swapFor.address));
        await factory.setFeeTo(feeReceiver.address);
        await feeReceiver.setSwapCommonBase(commonBase.address);

        // Set initial distributions
        await setDistributions([1, 3, 6]);

        // Create pairs
        const pair0 = Fixtures.set('pair0', await addPair(factory, tokenA, tokenB, 5, 10));
        Fixtures.set('pair1', await addPair(factory, commonBase, swapFor, 5, 10));
        Fixtures.set('pair2', await addPair(factory, tokenA, commonBase, 5, 10));
        Fixtures.set('pair3', await addPair(factory, tokenB, commonBase, 5, 10));
        Fixtures.set('pair4', await addPair(factory, tokenA, other, 5, 10));
        Fixtures.set('pair5', await addPair(factory, other, commonBase, 5, 10));
        Fixtures.set('pair6', await addPair(factory, tokenA, commonBase2, 10, 20));
        Fixtures.set('pair7', await addPair(factory, tokenB, commonBase2, 10, 20));
        Fixtures.set('pair8', await addPair(factory, commonBase2, swapFor, 10, 20));
        Fixtures.set('pair9', await addPair(factory, tokenA, swapFor, 25, 100));

        // Do initial swap
        await tokenA.transfer(pair0.address, expandTo18Decimals(1));
        const [amount0, amount1] = tokenA === token0 ? ['0', '1662497915624478906'] : ['1662497915624478906', '0'];
        await pair0.swap(amount0, amount1, account.address, '0x');
        await addLiquidity(pair0, tokenA, tokenB, expandTo18Decimals(5), expandTo18Decimals(10));
    });

    async function setDistributions(_shares: number[]) {
        const recipients = [await getAccountAddress(6), await getAccountAddress(7), await getAccountAddress(8)];
        const baseShare = BigNumber.from(10).pow(17);
        const shares = [baseShare.mul(_shares[0]), baseShare.mul(_shares[1]), baseShare.mul(_shares[2])];
        await Fixtures.use('feeReceiver').setDistributions(recipients, shares);
    }

    async function addPair(factory: Contract, tokenA: Contract, tokenB: Contract, amountA: number, amountB: number): Promise<Contract> {
        const pair = await createPair(factory, tokenA.address, tokenB.address);
        await addLiquidity(pair, tokenA, tokenB, expandTo18Decimals(amountA), expandTo18Decimals(amountB));
        return pair;
    }

    async function addLiquidity(pair: Contract, tokenA: Contract, tokenB: Contract, tokenAAmount: BigNumber, tokenBAmount: BigNumber) {
        await tokenA.transfer(pair.address, tokenAAmount)
        await tokenB.transfer(pair.address, tokenBAmount)
        await pair.mint(await getAccountAddress(0));
    }

    async function swapForBalance(account: number): Promise<BigNumber> {
        return await Fixtures.use('swapFor').balanceOf(await getAccountAddress(account));
    }

    async function getAccountAddress(account: number): Promise<string> {
        return (await getAccount(account)).address;
    }

    it('swapCommonBase', async () => {
        await expect(await Fixtures.use('feeReceiver').swapCommonBase()).to.eq(Fixtures.use('commonBase').address);
    });

    it('distributionsLength, distributions', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        await expect(await feeReceiver.distributionsLength()).to.eq(3);
        await expect((await feeReceiver.getDistributions()).length).to.eq(3);
    });

    it('prootcolFee', async () => {
        await expect(await Fixtures.use('pair0').balanceOf(Fixtures.use('feeReceiver').address)).to.eq('353615278793683');
    });

    it('swapAndDistribute:tokens', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');

        await expect(feeReceiver.swapAndDistributeWithTokens([Fixtures.use('tokenA').address], [Fixtures.use('tokenB').address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair2'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('318039710061106');
        await expect(await swapForBalance(7)).to.eq('954119130183320');
        await expect(await swapForBalance(8)).to.eq('1908238260366640');
    });

    it('swapAndDistribute:pair', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');

        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair2'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('318039710061106');
        await expect(await swapForBalance(7)).to.eq('954119130183320');
        await expect(await swapForBalance(8)).to.eq('1908238260366640');
    });

    it('setDistributions', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');

        await setDistributions([3, 6, 1]);

        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair2'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('954119130183320');
        await expect(await swapForBalance(7)).to.eq('1908238260366640');
        await expect(await swapForBalance(8)).to.eq('318039710061106');
    });

    it('setExecutorAllowance', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');
        const account0 = await getAccount(0);
        const account1 = await getAccount(1);

        await expect(feeReceiver.connect(account1).swapAndDistribute([pair0.address]))
            .to.be.revertedWith("Not executor");

        await feeReceiver.connect(account0).setExecutorAllowance(account1.address, true);
        await expect(feeReceiver.connect(account1).swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair2'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap');

        await feeReceiver.connect(account0).setExecutorAllowance(account1.address, false);
        await expect(feeReceiver.connect(account1).swapAndDistribute([pair0.address]))
            .to.be.revertedWith("Not executor");
    });

    it('setExecutorRestricted', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');
        const account0 = await getAccount(0);
        const account1 = await getAccount(1);

        await expect(feeReceiver.connect(account1).swapAndDistribute([pair0.address]))
            .to.be.revertedWith("Not executor");

        await feeReceiver.connect(account0).setExecutorRestricted(false);
        await expect(feeReceiver.connect(account1).swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair2'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap');

        await feeReceiver.connect(account0).setExecutorRestricted(true);
        await expect(feeReceiver.connect(account1).swapAndDistribute([pair0.address]))
            .to.be.revertedWith("Not executor");
    });

    it('setSwapMaxPriceImpact', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');

        await feeReceiver.setSwapMaxPriceImpact(100);
        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn');
        
        await expect(await pair0.balanceOf(feeReceiver.address)).to.eq(0);
        await expect(await Fixtures.use('tokenA').balanceOf(feeReceiver.address)).to.eq('300037509377930');
        await expect(await Fixtures.use('tokenB').balanceOf(feeReceiver.address)).to.eq('500176223055331');
        await expect(await Fixtures.use('commonBase').balanceOf(feeReceiver.address)).to.eq(0);
        await expect(await swapForBalance(6)).to.eq(0);
        await expect(await swapForBalance(7)).to.eq(0);
        await expect(await swapForBalance(8)).to.eq(0);
    });

    it('setSwapPathOverrides:empty', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');
        const tokenA = Fixtures.use('tokenA');

        await expect(feeReceiver.setSwapPathOverrides(tokenA.address, [tokenA.address])).to.be.revertedWith('Invalid path');
        await feeReceiver.setSwapPathOverrides(tokenA.address, []);

        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair2'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('318039710061106');
        await expect(await swapForBalance(7)).to.eq('954119130183320');
        await expect(await swapForBalance(8)).to.eq('1908238260366640');
    });

    it('setSwapCommonBase', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');

        await feeReceiver.setSwapCommonBase(Fixtures.use('commonBase2').address);
        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair6'), 'Swap')
            .emit(Fixtures.use('pair7'), 'Swap')
            .emit(Fixtures.use('pair8'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('318103772486687');
        await expect(await swapForBalance(7)).to.eq('954311317460062');
        await expect(await swapForBalance(8)).to.eq('1908622634920124');
    });

    it('setSwapPathOverrides:path:other', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');
        const tokenA = Fixtures.use('tokenA');

        const path = [
            tokenA.address,
            Fixtures.use('other').address,
            Fixtures.use('commonBase').address,
            Fixtures.use('swapFor').address,
        ];
        await feeReceiver.setSwapPathOverrides(tokenA.address, path);

        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap')
            .emit(Fixtures.use('pair4'), 'Swap')
            .emit(Fixtures.use('pair5'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('258600728151600');
        await expect(await swapForBalance(7)).to.eq('775802184454800');
        await expect(await swapForBalance(8)).to.eq('1551604368909601');
    });

    it('setSwapPathOverrides:path:direct', async () => {
        const feeReceiver = Fixtures.use('feeReceiver');
        const pair0 = Fixtures.use('pair0');
        const tokenA = Fixtures.use('tokenA');

        const path = [
            tokenA.address,
            Fixtures.use('swapFor').address,
        ];
        await feeReceiver.setSwapPathOverrides(tokenA.address, path);

        await expect(feeReceiver.swapAndDistribute([pair0.address]))
            .emit(pair0, 'Burn')
            .emit(feeReceiver, 'Distribute')
            .emit(Fixtures.use('pair1'), 'Swap')
            .emit(Fixtures.use('pair3'), 'Swap')
            .emit(Fixtures.use('pair9'), 'Swap');

        await expect(await swapForBalance(6)).to.eq('318466027141962');
        await expect(await swapForBalance(7)).to.eq('955398081425886');
        await expect(await swapForBalance(8)).to.eq('1910796162851772');
    });

    it('rescueERC20', async () => {
        const pair0 = Fixtures.use('pair0');
        const account = await getAccountAddress(4);
        await Fixtures.use('feeReceiver').rescueERC20(pair0.address, account, 10000);
        await expect(await pair0.balanceOf(account)).to.eq('10000');
    });
});