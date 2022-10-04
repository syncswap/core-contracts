import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals, mineBlock, encodePrice, MINIMUM_LIQUIDITY, ZERO_ADDRESS } from './shared/utilities';
import { pairFixture } from './shared/fixtures';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

chai.use(solidity);
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

describe('Pool', () => {
  let wallet: SignerWithAddress;
  let other: SignerWithAddress;

  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];
  });

  let factory: Contract;
  let token0: Contract;
  let token1: Contract;
  let stablePair: Contract;
  let volatilePair: Contract;

  beforeEach(async () => {
    const fixture = await pairFixture(wallet);
    factory = fixture.factory;
    token0 = fixture.token0;
    token1 = fixture.token1;
    stablePair = fixture.stablePair;
    volatilePair = fixture.volatilePair;
  });

  it('mint', async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await token0.transfer(volatilePair.address, token0Amount);
    await token1.transfer(volatilePair.address, token1Amount);

    const expectedLiquidity = expandTo18Decimals(2);
    await expect(volatilePair.mint(wallet.address))
      .to.emit(volatilePair, 'Transfer')
      .withArgs(ZERO_ADDRESS, ZERO_ADDRESS, MINIMUM_LIQUIDITY)
      .to.emit(volatilePair, 'Transfer')
      .withArgs(ZERO_ADDRESS, wallet.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(volatilePair, 'Sync')
      .withArgs(token0Amount, token1Amount)
      .to.emit(volatilePair, 'Mint')
      .withArgs(wallet.address, token0Amount, token1Amount);

    expect(await volatilePair.totalSupply()).to.eq(expectedLiquidity);
    expect(await volatilePair.balanceOf(wallet.address)).to.eq(expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    expect(await token0.balanceOf(volatilePair.address)).to.eq(token0Amount);
    expect(await token1.balanceOf(volatilePair.address)).to.eq(token1Amount);

    const reserve0 = await volatilePair.reserve0();
    expect(reserve0).to.eq(token0Amount);

    const reserve1 = await volatilePair.reserve1();
    expect(reserve1).to.eq(token1Amount);
  });

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber): Promise<void> {
    await token0.transfer(volatilePair.address, token0Amount);
    await token1.transfer(volatilePair.address, token1Amount);
    await volatilePair.mint(wallet.address);
  };

  const swapTestCases: BigNumber[][] = [
    [1, 5, 10, '1662497915624478906'],
    [1, 10, 5, '453305446940074565'],

    [2, 5, 10, '2851015155847869602'],
    [2, 10, 5, '831248957812239453'],

    [1, 10, 10, '906610893880149131'],
    [1, 100, 100, '987158034397061298'],
    [1, 1000, 1000, '996006981039903216']
  ].map(a => a.map(n => (typeof n === 'string' ? BigNumber.from(n) : expandTo18Decimals(n))));

  swapTestCases.forEach((swapTestCase, i) => {
    it(`getInputPrice:${i}`, async () => {
      const [swapAmount, token0Amount, token1Amount, expectedOutputAmount] = swapTestCase;
      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(volatilePair.address, swapAmount);
      await expect(volatilePair.swap(0, expectedOutputAmount.add(1), wallet.address, wallet.address, '0x')).to.be.revertedWith(
        'K'
      );
      await volatilePair.swap(0, expectedOutputAmount, wallet.address, wallet.address, '0x');
    });
  });

  const optimisticTestCases: BigNumber[][] = [
    ['997000000000000000', 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .997)
    ['997000000000000000', 10, 5, 1],
    ['997000000000000000', 5, 5, 1],
    [1, 5, 5, '1003009027081243732'] // given amountOut, amountIn = ceiling(amountOut / .997)
  ].map(a => a.map(n => (typeof n === 'string' ? BigNumber.from(n) : expandTo18Decimals(n))))
  optimisticTestCases.forEach((optimisticTestCase, i) => {
    it(`optimistic:${i}`, async () => {
      const [outputAmount, token0Amount, token1Amount, inputAmount] = optimisticTestCase
      await addLiquidity(token0Amount, token1Amount)
      await token0.transfer(volatilePair.address, inputAmount)
      // add 2 instead due to fee rounding
      await expect(volatilePair.swap(outputAmount.add(2), 0, wallet.address, wallet.address, '0x')).to.be.revertedWith(
        'K'
      )
      await volatilePair.swap(outputAmount, 0, wallet.address, wallet.address, '0x')
    })
  });

  it('swap:token0', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = BigNumber.from('1662497915624478906')
    await token0.transfer(volatilePair.address, swapAmount)
    await expect(volatilePair.swap(0, expectedOutputAmount, wallet.address, wallet.address, '0x'))
      .to.emit(token1, 'Transfer')
      .withArgs(volatilePair.address, wallet.address, expectedOutputAmount)
      .to.emit(volatilePair, 'Sync')
      .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
      .to.emit(volatilePair, 'Swap')
      .withArgs(wallet.address, swapAmount, 0, 0, expectedOutputAmount, wallet.address)

    const reserve0 = await volatilePair.reserve0();
    expect(reserve0).to.eq(token0Amount.add(swapAmount));

    const reserve1 = await volatilePair.reserve1();
    expect(reserve1).to.eq(token1Amount.sub(expectedOutputAmount));

    const fees = '600000000000000';
    expect(await token0.balanceOf(volatilePair.address)).to.eq(token0Amount.add(swapAmount).sub(fees))
    expect(await token1.balanceOf(volatilePair.address)).to.eq(token1Amount.sub(expectedOutputAmount))
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))
  });

  it('swap:token1', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = BigNumber.from('453305446940074565')
    await token1.transfer(volatilePair.address, swapAmount)
    await expect(volatilePair.swap(expectedOutputAmount, 0, wallet.address, wallet.address, '0x'))
      .to.emit(token0, 'Transfer')
      .withArgs(volatilePair.address, wallet.address, expectedOutputAmount)
      .to.emit(volatilePair, 'Sync')
      .withArgs(token0Amount.sub(expectedOutputAmount), token1Amount.add(swapAmount))
      .to.emit(volatilePair, 'Swap')
      .withArgs(wallet.address, 0, swapAmount, expectedOutputAmount, 0, wallet.address)

    const reserve0 = await volatilePair.reserve0();
    expect(reserve0).to.eq(token0Amount.sub(expectedOutputAmount));

    const reserve1 = await volatilePair.reserve1();
    expect(reserve1).to.eq(token1Amount.add(swapAmount));

    expect(await token0.balanceOf(volatilePair.address)).to.eq(token0Amount.sub(expectedOutputAmount))
    const fees = '600000000000000';
    expect(await token1.balanceOf(volatilePair.address)).to.eq(token1Amount.add(swapAmount).sub(fees))
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).add(expectedOutputAmount))
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).sub(swapAmount))
  });

  it('swap:gas:0', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = BigNumber.from('453305446940074565')
    await token1.transfer(volatilePair.address, swapAmount)
    await mineBlock((await ethers.provider.getBlock('latest')).timestamp + 1)

    const tx = await volatilePair.swap(expectedOutputAmount, 0, wallet.address, wallet.address, '0x')
    const receipt = await tx.wait()
    expect(receipt.gasUsed).to.eq(110733) // 73462
  });

  it('burn', async () => {
    const token0Amount = expandTo18Decimals(3)
    const token1Amount = expandTo18Decimals(3)
    await addLiquidity(token0Amount, token1Amount)

    const expectedLiquidity = expandTo18Decimals(3)
    await volatilePair.transfer(volatilePair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    await expect(volatilePair.burn(wallet.address))
      .to.emit(volatilePair, 'Transfer')
      .withArgs(volatilePair.address, ZERO_ADDRESS, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(token0, 'Transfer')
      .withArgs(volatilePair.address, wallet.address, token0Amount.sub(1000))
      .to.emit(token1, 'Transfer')
      .withArgs(volatilePair.address, wallet.address, token1Amount.sub(1000))
      .to.emit(volatilePair, 'Sync')
      .withArgs(1000, 1000)
      .to.emit(volatilePair, 'Burn')
      .withArgs(wallet.address, token0Amount.sub(1000), token1Amount.sub(1000), wallet.address)

    expect(await volatilePair.balanceOf(wallet.address)).to.eq(0)
    expect(await volatilePair.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
    expect(await token0.balanceOf(volatilePair.address)).to.eq(1000)
    expect(await token1.balanceOf(volatilePair.address)).to.eq(1000)
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(1000))
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(1000))
  });

  it('feeTo:off', async () => {
    const token0Amount = expandTo18Decimals(1000)
    const token1Amount = expandTo18Decimals(1000)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = BigNumber.from('996006981039903216')
    await token1.transfer(volatilePair.address, swapAmount)
    await volatilePair.swap(expectedOutputAmount, 0, wallet.address, wallet.address, '0x')

    const expectedLiquidity = expandTo18Decimals(1000)
    await volatilePair.transfer(volatilePair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    await volatilePair.burn(wallet.address)
    expect(await volatilePair.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
  });

  it('feeTo:on', async () => {
    expect(await factory.feeRecipient()).to.eq(other.address);

    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1000);
    const token1Amount = expandTo18Decimals(1000);
    await addLiquidity(token0Amount, token1Amount);
    expect(await volatilePair.balanceOf(wallet.address)).to.eq(expandTo18Decimals(1000).sub(MINIMUM_LIQUIDITY));

    // Perform swap & transfer protocol fees.
    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = BigNumber.from('996006981039903216');
    await token1.transfer(volatilePair.address, swapAmount);
    await volatilePair.swap(expectedOutputAmount, 0, wallet.address, wallet.address, '0x');

    // Burn initial liquidity.
    const expectedLiquidity = expandTo18Decimals(1000);
    await volatilePair.transfer(volatilePair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    await volatilePair.burn(wallet.address);

    // Check balances.
    expect(await volatilePair.totalSupply()).to.eq(1000);
    expect(await token0.balanceOf(other.address)).to.eq(0);
    expect(await token1.balanceOf(other.address)).to.eq('600000000000000');

    expect(await token0.balanceOf(volatilePair.address)).to.eq(BigNumber.from(1000));
    expect(await token1.balanceOf(volatilePair.address)).to.eq(BigNumber.from(1001)); // add 1 due to fee rounding
  });
})