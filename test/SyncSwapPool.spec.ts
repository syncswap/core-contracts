import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals, mineBlock, encodePrice, MINIMUM_LIQUIDITY, ZERO_ADDRESS, ZERO } from './shared/utilities';
import { pairFixture } from './shared/fixtures';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { calculateLiquidityToMint, calculatePoolTokens, getAmountOut, getSwapFee } from './shared/helper';

chai.use(solidity);
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

let wallet: SignerWithAddress;
let other: SignerWithAddress;
let factory: Contract;
let token0: Contract;
let token1: Contract;

async function expectDefaultValues(stable: boolean, pool: Contract) {
  expect(await pool.factory()).to.eq(factory.address);
  expect(await pool.token0()).to.eq(token0.address);
  expect(await pool.token1()).to.eq(token1.address);
  expect(await pool.A()).to.eq(stable ? '400000' : 0);
  expect(await pool.token0PrecisionMultiplier()).to.eq(stable ? 1 : 1);
  expect(await pool.token1PrecisionMultiplier()).to.eq(stable ? 1 : 1);
  expect(await pool.reserve0()).to.eq(0);
  expect(await pool.reserve1()).to.eq(0);
  expect(await pool.invariantLast()).to.eq(0);
}

async function addLiquidity(
  pool: Contract,
  token0Amount: BigNumber,
  token1Amount: BigNumber,
  expectedLiquidity?: string,
  expectedFee0?: string,
  expectedFee1?: string
) {
  const balance0Before = await token0.balanceOf(pool.address);
  const balance1Before = await token1.balanceOf(pool.address);
  const totalSupplyBefore = await pool.totalSupply();
  const liquidityBefore = await pool.balanceOf(wallet.address);

  // Prefund tokens.
  await token0.transfer(pool.address, token0Amount);
  await token1.transfer(pool.address, token1Amount);
  expect(await token0.balanceOf(pool.address)).to.eq(token0Amount.add(balance0Before));
  expect(await token1.balanceOf(pool.address)).to.eq(token1Amount.add(balance1Before));

  const calculated = await calculateLiquidityToMint(
    pool,
    token0Amount,
    token1Amount
  );
  if (expectedLiquidity) {
    expect(calculated.liquidity).to.eq(expectedLiquidity);
  }
  if (expectedFee0) {
    expect(calculated.fee0).to.eq(expectedFee0);
  }
  if (expectedFee1) {
    expect(calculated.fee1).to.eq(expectedFee1);
  }

  if (balance0Before.isZero()) {
    await expect(pool.mint(wallet.address))
      .to.emit(pool, 'Transfer')
      .withArgs(ZERO_ADDRESS, ZERO_ADDRESS, MINIMUM_LIQUIDITY)
      .to.emit(pool, 'Transfer')
      .withArgs(ZERO_ADDRESS, wallet.address, calculated.liquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(pool, 'Sync')
      .withArgs(token0Amount, token1Amount)
      .to.emit(pool, 'Mint')
      .withArgs(wallet.address, token0Amount, token1Amount, calculated.liquidity.sub(MINIMUM_LIQUIDITY), wallet.address);
  } else {
    await expect(pool.mint(wallet.address))
      .to.emit(pool, 'Transfer')
      .withArgs(ZERO_ADDRESS, wallet.address, calculated.liquidity)
      .to.emit(pool, 'Sync')
      .withArgs(token0Amount.add(balance0Before), token1Amount.add(balance1Before))
      .to.emit(pool, 'Mint')
      .withArgs(wallet.address, token0Amount, token1Amount, calculated.liquidity, wallet.address);
  }

  expect(await token0.balanceOf(pool.address)).to.eq(token0Amount.add(balance0Before));
  expect(await token1.balanceOf(pool.address)).to.eq(token1Amount.add(balance1Before));

  expect(await pool.totalSupply()).to.eq(
    calculated.liquidity.add(totalSupplyBefore).add(calculated.protocolFee) // Add if has protocol fee minted.
  );
  const liquidityAfter = (
    balance0Before.isZero() ?
      calculated.liquidity.sub(MINIMUM_LIQUIDITY) :
      calculated.liquidity.add(liquidityBefore)
  );
  expect(await pool.balanceOf(wallet.address)).to.eq(liquidityAfter);

  expect(await pool.reserve0()).to.eq(token0Amount.add(balance0Before));
  expect(await pool.reserve1()).to.eq(token1Amount.add(balance1Before));
}

async function removeLiquiditySingle(
  pool: Contract,
  liquidity: BigNumber,
  tokenOut: string,
  expectedAmount0: string,
  expectedAmount1: string
) {
  const liquidityBalance = await pool.balanceOf(wallet.address);

  const totalSupply = await pool.totalSupply();
  const poolBalance0 = await token0.balanceOf(pool.address);
  const poolBalance1 = await token1.balanceOf(pool.address);

  const token0AmountBalanced = calculatePoolTokens(liquidity, poolBalance0, totalSupply);
  const token1AmountBalanced = calculatePoolTokens(liquidity, poolBalance1, totalSupply);

  const swapFee = await getSwapFee(pool);
  const token0Amount = (
    tokenOut == token0.address ?
    token0AmountBalanced.add(getAmountOut({
      amountIn: token1AmountBalanced,
      reserveIn: poolBalance1.sub(token1AmountBalanced),
      reserveOut: poolBalance0.sub(token0AmountBalanced),
      swapFee: swapFee,
      A: await pool.A(),
      tokenInPrecisionMultiplier: await pool.token1PrecisionMultiplier(),
      tokenOutPrecisionMultiplier: await pool.token0PrecisionMultiplier()
    })) :
    ZERO
  );
  const token1Amount = (
    tokenOut == token1.address ?
    token1AmountBalanced.add(getAmountOut({
      amountIn: token0AmountBalanced,
      reserveIn: poolBalance0.sub(token0AmountBalanced),
      reserveOut: poolBalance1.sub(token1AmountBalanced),
      swapFee: swapFee,
      A: await pool.A(),
      tokenInPrecisionMultiplier: await pool.token0PrecisionMultiplier(),
      tokenOutPrecisionMultiplier: await pool.token1PrecisionMultiplier()
    })) :
    ZERO
  );
  expect(token0Amount).to.eq(expectedAmount0);
  expect(token1Amount).to.eq(expectedAmount1);

  await pool.transfer(pool.address, liquidity);
  expect(await pool.balanceOf(wallet.address)).to.eq(liquidityBalance.sub(liquidity));
  expect(await pool.balanceOf(pool.address)).to.eq(liquidity);

  const isToken0Out = tokenOut == token0.address;
  const expectedTokenOutAmount = isToken0Out ? token0Amount : token1Amount;

  await expect(pool.burnSingle(tokenOut, wallet.address))
    .to.emit(pool, 'Transfer')
    .withArgs(pool.address, ZERO_ADDRESS, liquidity)
    .to.emit(isToken0Out ? token0 : token1, 'Transfer')
    .withArgs(pool.address, wallet.address, expectedTokenOutAmount)
    .to.emit(pool, 'Sync')
    .withArgs(poolBalance0.sub(token0Amount), poolBalance1.sub(token1Amount))
    .to.emit(pool, 'Burn')
    .withArgs(wallet.address, token0Amount, token1Amount, liquidity, wallet.address);
}

async function swap(
  pool: Contract,
  token0AmountLiquidity: BigNumber,
  token1AmountLiquidity: BigNumber,
  tokenIn: Contract,
  amountIn: BigNumber,
  expectedAmountOut: BigNumber | string
) {
  // Add initial liquidity.
  await addLiquidity(pool, token0AmountLiquidity, token1AmountLiquidity);

  const poolTokenInBalanceBefore = await tokenIn.balanceOf(pool.address);
  const isToken0In = tokenIn.address == token0.address;
  const tokenOut = isToken0In ? token1 : token0;
  const poolTokenOutBalanceBefore = await tokenOut.balanceOf(pool.address);

  // Prefund the pool.
  await tokenIn.transfer(pool.address, amountIn);
  expect(await tokenIn.balanceOf(pool.address)).to.eq(poolTokenInBalanceBefore.add(amountIn));

  const [reserve0, reserve1] = [
    await pool.reserve0(),
    await pool.reserve1()
  ];
  const [reserveIn, reserveOut] = (
    isToken0In ? [reserve0, reserve1] : [reserve1, reserve0]
  );

  const [token0PrecisionMultiplier, token1PrecisionMultiplier] = [
    await pool.token0PrecisionMultiplier(),
    await pool.token1PrecisionMultiplier()
  ];
  const [tokenInPrecisionMultiplier, tokenOutPrecisionMultiplier] = (
    isToken0In ? [token0PrecisionMultiplier, token1PrecisionMultiplier] : [token1PrecisionMultiplier, token0PrecisionMultiplier]
  );

  const amountOut = getAmountOut({
    amountIn: amountIn,
    reserveIn: reserveIn,
    reserveOut: reserveOut,
    swapFee: await getSwapFee(pool),
    A: await pool.A(),
    tokenInPrecisionMultiplier: tokenInPrecisionMultiplier,
    tokenOutPrecisionMultiplier: tokenOutPrecisionMultiplier
  });
  expect(amountOut).to.eq(expectedAmountOut);

  const [amount0Out, amount1Out] = isToken0In ? [0, amountOut] : [amountOut, 0];
  const [amount0In, amount1In] = isToken0In ? [amountIn, 0] : [0, amountIn];

  await expect(pool.swap(token0.address, wallet.address))
    .to.emit(pool, 'Swap')
    .withArgs(wallet.address, amount0In, amount1In, amount0Out, amount1Out, wallet.address);

  expect(await tokenIn.balanceOf(pool.address)).to.eq(poolTokenInBalanceBefore.add(amountIn));
  expect(await tokenOut.balanceOf(pool.address)).to.eq(poolTokenOutBalanceBefore.sub(amountOut));
}

async function removeLiquidity(
  pool: Contract,
  liquidity: BigNumber,
  expectedAmount0: string,
  expectedAmount1: string
) {
  const liquidityBalance = await pool.balanceOf(wallet.address);
  const balance0Before = await token0.balanceOf(wallet.address);
  const balance1Before = await token1.balanceOf(wallet.address);

  const totalSupply = await pool.totalSupply();
  const poolBalance0 = await token0.balanceOf(pool.address);
  const poolBalance1 = await token1.balanceOf(pool.address);

  const expectedToken0Amount = calculatePoolTokens(liquidity, poolBalance0, totalSupply);
  const expectedToken1Amount = calculatePoolTokens(liquidity, poolBalance1, totalSupply);
  expect(expectedToken0Amount).to.eq(expectedAmount0);
  expect(expectedToken1Amount).to.eq(expectedAmount1);

  await pool.transfer(pool.address, liquidity);
  expect(await pool.balanceOf(wallet.address)).to.eq(liquidityBalance.sub(liquidity));
  expect(await pool.balanceOf(pool.address)).to.eq(liquidity);

  await expect(pool.burn(wallet.address))
    .to.emit(pool, 'Transfer')
    .withArgs(pool.address, ZERO_ADDRESS, liquidity)
    .to.emit(token0, 'Transfer')
    .withArgs(pool.address, wallet.address, expectedToken0Amount)
    .to.emit(token1, 'Transfer')
    .withArgs(pool.address, wallet.address, expectedToken1Amount)
    .to.emit(pool, 'Sync')
    .withArgs(poolBalance0.sub(expectedToken0Amount), poolBalance1.sub(expectedToken1Amount))
    .to.emit(pool, 'Burn')
    .withArgs(wallet.address, expectedToken0Amount, expectedToken1Amount, liquidity, wallet.address);

  expect(await pool.balanceOf(pool.address)).to.eq(0);
  expect(await pool.totalSupply()).to.eq(totalSupply.sub(liquidity));

  expect(await token0.balanceOf(pool.address)).to.eq(poolBalance0.sub(expectedToken0Amount));
  expect(await token1.balanceOf(pool.address)).to.eq(poolBalance1.sub(expectedToken1Amount));

  expect(await token0.balanceOf(wallet.address)).to.eq(balance0Before.add(expectedToken0Amount));
  expect(await token1.balanceOf(wallet.address)).to.eq(balance1Before.add(expectedToken1Amount));
}

describe('Stable Pool', () => {
  let pool: Contract;

  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];
  });

  beforeEach(async () => {
    const fixture = await pairFixture(wallet, other);
    factory = fixture.factory;
    token0 = fixture.token0;
    token1 = fixture.token1;
    pool = fixture.stablePair;
  });

  it("Should returns expected pool metadata", async () => {
    await expectDefaultValues(true, pool);
  });

  it("Should revert on mint liquidity without token", async () => {
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should revert on mint liquidity with only token0", async () => {
    await token0.transfer(pool.address, 1);
    await expect(pool.mint(wallet.address)).to.be.reverted;

    await token0.transfer(pool.address, expandTo18Decimals(1));
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should revert on mint liquidity with only token1", async () => {
    await token1.transfer(pool.address, 1);
    await expect(pool.mint(wallet.address)).to.be.reverted;

    await token1.transfer(pool.address, expandTo18Decimals(1));
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should revert on mint liquidity (minimal tokens)", async () => {
    await token0.transfer(pool.address, 100);
    await token1.transfer(pool.address, 100);
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.be.eq(0);
  });

  it("Should NOT revert on mint liquidity (minimal tokens)", async () => {
    await token0.transfer(pool.address, 1000);
    await token1.transfer(pool.address, 1000);
    await expect(pool.mint(wallet.address)).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq(2000);
  });

  it("Should revert on mint liquidity (maximum tokens)", async () => {
    await token0.transfer(pool.address, expandTo18Decimals('1000000000000000000'));
    await token1.transfer(pool.address, expandTo18Decimals('1000000000000000000'));
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should NOT revert on mint liquidity (maximum tokens)", async () => {
    await token0.transfer(pool.address, expandTo18Decimals('100000000000000000'));
    await token1.transfer(pool.address, expandTo18Decimals('100000000000000000'));
    await expect(pool.mint(wallet.address)).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq('200000000000000000000000000000000000');
  });

  it("Should revert on mint liquidity (edge case)", async () => {
    await token0.transfer(pool.address, 1);
    await token1.transfer(pool.address, expandTo18Decimals('100000000'));
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should NOT revert on mint liquidity (edge case)", async () => {
    await token0.transfer(pool.address, 1);
    await token1.transfer(pool.address, expandTo18Decimals('10000000'));
    await expect(pool.mint(wallet.address)).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq('6839902227232610255');
  });

  it("Should mint expected liquidity", async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');
    expect(await pool.totalSupply()).to.eq('4999996484391204744');
  });

  it("Should mint expected liquidity (evenly)", async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(1);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');
  });

  it("Should mint expected liquidity (edge case)", async () => {
    const token0Amount = BigNumber.from(1);
    const token1Amount = expandTo18Decimals('10000000');
    await addLiquidity(pool, token0Amount, token1Amount, '6839902227232610255', '0', '0');
    expect(await pool.totalSupply()).to.eq('6839902227232610255');
  });

  it("Should mint expected liquidity balanced", async () => {
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');
    expect(await pool.totalSupply()).to.eq('4999996484391204744');

    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204745', '0', '0');
    expect(await pool.totalSupply()).to.eq('9999992968782409489');

    token0Amount = expandTo18Decimals(5);
    token1Amount = expandTo18Decimals(20);
    await addLiquidity(pool, token0Amount, token1Amount, '24999982421956023724', '0', '0');
    expect(await pool.totalSupply()).to.eq('34999975390738433213');
  });

  it("Should mint expected liquidity unbalanced", async () => {
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');
    expect(await pool.totalSupply()).to.eq('4999996484391204744');

    token0Amount = expandTo18Decimals(4);
    token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '7996823251116117710', '1500000000000000', '0');
    expect(await pool.totalSupply()).to.eq('12997269643342997687');

    // Add calculated balanced liquidity expects no fee.
    const reserve0 = await pool.reserve0();
    const reserve1 = await pool.reserve1();
    token0Amount = expandTo18Decimals(1);
    token1Amount = token0Amount.mul(reserve1).div(reserve0);
    expect(token1Amount).to.eq('1600000000000000000');
    await addLiquidity(pool, token0Amount, token1Amount, '2599453928668599537', '0', '0');
    expect(await pool.totalSupply()).to.eq('15596723572011597224');
  });

  it("Should burn some liquidity", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    await removeLiquidity(pool, BigNumber.from(500000), '100000', '400000');
  });

  it("Should burn some liquidity (edge case)", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    await removeLiquidity(pool, BigNumber.from(1), '0', '0'); // no tokens received
    await removeLiquidity(pool, BigNumber.from(10), '2', '8');
  });

  it("Should burn all liquidity", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('4999996484391203744');

    await removeLiquidity(pool, liquidity, '999999999999999799', '3999999999999999199');
  });

  it("Should burn some liquidity single for token0", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('4999996484391203744');

    // received 100000 + 399596 swapped
    await removeLiquiditySingle(pool, BigNumber.from(500000), token0.address, '499596', '0');
    expect(await pool.balanceOf(wallet.address)).to.eq('4999996484390703744');
  });

  it("Should burn some liquidity single for token1", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('4999996484391203744');

    // received 400000 + 99900 swapped
    await removeLiquiditySingle(pool, BigNumber.from(500000), token1.address, '0', '499900');
    expect(await pool.balanceOf(wallet.address)).to.eq('4999996484390703744');
  });

  it("Should burn all liquidity single for token0", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('4999996484391203744');

    // received 999999999999999799 + 200 swapped
    await removeLiquiditySingle(pool, liquidity, token0.address, '999999999999999999', '0');
    expect(await pool.balanceOf(wallet.address)).to.eq(0);
    expect(await pool.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  it("Should burn all liquidity single for token1", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4999996484391204744', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('4999996484391203744');

    // received 3999999999999999199 + 800 swapped
    await removeLiquiditySingle(pool, liquidity, token1.address, '0', '3999999999999999999');
    expect(await pool.balanceOf(wallet.address)).to.eq(0);
    expect(await pool.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  const swapTestCases: BigNumber[][] = [
    // unbalanced
    [1, 4, 1, '999003254108072772'],
    [10, 5, 1, '998997127410384060'],
    [1, 100, 1, '1000592614718446373'],
    [4, 1, 1, '996666012010949335'],
    [5, 10, 1, '999001561410388341'],
    [100, 1, 1, '944640390573834075'],
    ['1', 1000, 1, '999999999999998983010'],

    // balanced
    [1, 1, 1, '998276759544685493'],
    [10, 10, 1, '998999747985341147'],
    [100, 100, 10, '9989997479853411474'],
    [1000, 1000, 1, '998999997505001253'],

    // zero input
    [1, 1, 0, 0],
    [1000, 1000, 0, 0],
    [1000, 1, 0, 0],
    ['1000', '1000', 0, 0],
    ['1', 1000, 0, 0],
    [1, 100000000, 0, 0],

    // small input
    [1, 1000, '1', '0'],
    [1000, 1, '10', '7'],
    [1000, 1000, '1', '0'],
    [1000, 1000, '100', '99'],

    // big input
    [1, 1, 100, '999999999749474152'],
    ['1000', '1000', 1000, '999'],
    ['1000', '4000', 100000000, '3999'],
  ].map(a => a.map(n => (typeof n === 'string' ? BigNumber.from(n) : expandTo18Decimals(n))));

  swapTestCases.forEach((swapTestCase, i) => {
    it(`Should swap token0 for token1 - case ${i + 1}`, async () => {
      const [token0AmountLiquidity, token1AmountLiquidity, amountIn, amountOut] = swapTestCase;

      await swap(
        pool,
        token0AmountLiquidity,
        token1AmountLiquidity,
        token0,
        amountIn,
        amountOut
      );
    });
  });
});

describe('Volatile Pool', () => {
  let pool: Contract;

  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];
  });

  beforeEach(async () => {
    const fixture = await pairFixture(wallet, other);
    factory = fixture.factory;
    token0 = fixture.token0;
    token1 = fixture.token1;
    pool = fixture.volatilePair;
  });

  it("Should returns expected pool metadata", async () => {
    await expectDefaultValues(false, pool);
  });

  it("Should revert on mint liquidity without token", async () => {
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should revert on mint liquidity with only token0", async () => {
    await token0.transfer(pool.address, 1);
    await expect(pool.mint(wallet.address)).to.be.reverted;

    await token0.transfer(pool.address, expandTo18Decimals(1));
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should revert on mint liquidity with only token1", async () => {
    await token1.transfer(pool.address, 1);
    await expect(pool.mint(wallet.address)).to.be.reverted;

    await token1.transfer(pool.address, expandTo18Decimals(1));
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.eq(0);
  });

  it("Should revert on mint liquidity (minimal tokens)", async () => {
    await token0.transfer(pool.address, 100);
    await token1.transfer(pool.address, 100);
    await expect(pool.mint(wallet.address)).to.be.reverted;
    expect(await pool.totalSupply()).to.be.eq(0);
  });

  it("Should NOT revert on mint liquidity (minimal tokens)", async () => {
    await token0.transfer(pool.address, 10000);
    await token1.transfer(pool.address, 10000);
    await expect(pool.mint(wallet.address)).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq(10000);
  });

  it("Should NOT revert on mint liquidity (maximum tokens)", async () => {
    await token0.transfer(pool.address, expandTo18Decimals('100000000000000000'));
    await token1.transfer(pool.address, expandTo18Decimals('100000000000000000'));
    await expect(pool.mint(wallet.address)).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq('100000000000000000000000000000000000');
  });

  it("Should NOT revert on mint liquidity (edge case)", async () => {
    await token0.transfer(pool.address, 1);
    await token1.transfer(pool.address, expandTo18Decimals('10000000'));
    await expect(pool.mint(wallet.address)).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq('3162277660168');
  });

  it("Should mint expected liquidity", async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');
  });

  it("Should mint expected liquidity (evenly)", async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(1);
    await addLiquidity(pool, token0Amount, token1Amount, '1000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('1000000000000000000');
  });

  it("Should mint expected liquidity (edge case)", async () => {
    const token0Amount = BigNumber.from(1);
    const token1Amount = expandTo18Decimals('10000000');
    await addLiquidity(pool, token0Amount, token1Amount, '3162277660168', '0', '0');
    expect(await pool.totalSupply()).to.eq('3162277660168');
  });

  it("Should mint expected liquidity balanced", async () => {
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');

    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('4000000000000000000');

    token0Amount = expandTo18Decimals(5);
    token1Amount = expandTo18Decimals(20);
    await addLiquidity(pool, token0Amount, token1Amount, '10000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('14000000000000000000');
  });

  it("Should mint expected liquidity unbalanced", async () => {
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');

    token0Amount = expandTo18Decimals(4);
    token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '4313274589435520146', '4500000000000000', '0');
    expect(await pool.totalSupply()).to.eq('6314620955946113419');

    // Add calculated balanced liquidity expects no fee.
    const reserve0 = await pool.reserve0();
    const reserve1 = await pool.reserve1();
    token0Amount = expandTo18Decimals(1);
    token1Amount = token0Amount.mul(reserve1).div(reserve0);
    expect(token1Amount).to.eq('1600000000000000000');
    await addLiquidity(pool, token0Amount, token1Amount, '1262924191189222684', '0', '0');
    expect(await pool.totalSupply()).to.eq('7577545147135336103');
  });

  it("Should burn some liquidity", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    await removeLiquidity(pool, BigNumber.from(500000), '250000', '1000000');
  });

  it("Should burn some liquidity (edge case)", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    await removeLiquidity(pool, BigNumber.from(1), '0', '2'); // no tokens received
    await removeLiquidity(pool, BigNumber.from(10), '5', '20');
  });

  it("Should burn all liquidity", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    await removeLiquidity(pool, liquidity, '999999999999999500', '3999999999999998000');
  });

  it("Should burn some liquidity single for token0", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    await removeLiquiditySingle(pool, BigNumber.from(500000), token0.address, '499249', '0');
    expect(await pool.balanceOf(wallet.address)).to.eq('1999999999999499000');
  });

  it("Should burn some liquidity single for token1", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    await removeLiquiditySingle(pool, BigNumber.from(500000), token1.address, '0', '1996999');
    expect(await pool.balanceOf(wallet.address)).to.eq('1999999999999499000');
  });

  it("Should burn all liquidity single for token0", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    // received 999999999999999799 + 200 swapped
    await removeLiquiditySingle(pool, liquidity, token0.address, '999999999999999999', '0');
    expect(await pool.balanceOf(wallet.address)).to.eq(0);
    expect(await pool.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  it("Should burn all liquidity single for token1", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await addLiquidity(pool, token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    // received 3999999999999999199 + 800 swapped
    await removeLiquiditySingle(pool, liquidity, token1.address, '0', '3999999999999999999');
    expect(await pool.balanceOf(wallet.address)).to.eq(0);
    expect(await pool.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  const swapTestCases: BigNumber[][] = [
    // unbalanced
    [1, 4, 1, '1996995493239859789'],
    [10, 5, 1, '453305446940074565'],
    [1, 100, 1, '49924887330996494742'],
    [4, 1, 1, '199519711827096257'],
    [5, 10, 1, '1662497915624478906'],
    [100, 1, 1, '9871580343970612'],
    ['1', 1000, 1, '999999999999999998996'],

    // balanced
    [1, 1, 1, '499248873309964947'],
    [10, 10, 1, '906610893880149131'],
    [100, 100, 10, '9066108938801491315'],
    [1000, 1000, 1, '996006981039903216'],

    // zero input
    [1, 1, 0, 0],
    [1000, 1000, 0, 0],
    [1000, 1, 0, 0],
    ['100000', '100000', 0, 0],
    ['1', 1000, 0, 0],
    [1, 100000000, 0, 0],

    // small input
    [1, 1000, '1', '996'],
    [1000, 1, '10', '0'],
    [1000, 1000, '1', '0'],
    [1000, 1000, '100', '99'],

    // big input
    [1, 1, 100, '990069513406156901'],
    ['100000', '100000', 1000, '99999'],
    ['1000', '4000', 100000000, '3999'],
  ].map(a => a.map(n => (typeof n === 'string' ? BigNumber.from(n) : expandTo18Decimals(n))));

  swapTestCases.forEach((swapTestCase, i) => {
    it(`Should swap token0 for token1 - case ${i + 1}`, async () => {
      const [token0AmountLiquidity, token1AmountLiquidity, amountIn, amountOut] = swapTestCase;

      await swap(
        pool,
        token0AmountLiquidity,
        token1AmountLiquidity,
        token0,
        amountIn,
        amountOut
      );
    });
  });
});