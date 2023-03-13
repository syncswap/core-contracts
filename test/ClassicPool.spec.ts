import chai, { expect } from 'chai';
import { BigNumber, BigNumberish, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals, MINIMUM_LIQUIDITY, ZERO_ADDRESS, ZERO } from './shared/utilities';
import { classicPoolFixture } from './shared/fixtures';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { calculateLiquidityToMint, calculatePoolTokens, getAmountOut, getSwapFee } from './shared/helper';
import { defaultAbiCoder } from 'ethers/lib/utils';

chai.use(solidity);
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

let wallet: SignerWithAddress;
let other: SignerWithAddress;

let weth: Contract;
let vault: Contract;
let master: Contract;
let factory: Contract;

let pool: Contract;
let token0: Contract;
let token1: Contract;

async function deposit(token: Contract, amount: BigNumberish) {
  // Transfer tokens to the vault.
  await token.transfer(vault.address, amount);

  // Notify the vault to deposit to the pool.
  await vault.deposit(token.address, pool.address);
}

async function balanceOf(token: Contract, owner: string | Contract | SignerWithAddress): Promise<BigNumber> {
  if (token != pool && (owner === pool || owner === pool.address)) {
    return await vault.balanceOf(token.address, pool.address);
  } else {
    return await token.balanceOf(typeof owner === 'string' ? owner : owner.address);
  }
}

function encodeAddress(address: string): string {
  return defaultAbiCoder.encode(["address"], [address]);
}

async function mint() {
  const data = encodeAddress(wallet.address);
  return pool.mint(data, wallet.address, ZERO_ADDRESS, '0x');
}

async function burn() {
  const data = defaultAbiCoder.encode(
    ["address", "uint8"], [wallet.address, 1] // 1 = UNWRAPPED
  );
  return pool.burn(data, wallet.address, ZERO_ADDRESS, '0x');
}

async function burnSingle(tokenOut: string) {
  const data = defaultAbiCoder.encode(
    ["address", "address", "uint8"], [tokenOut, wallet.address, 1] // 1 = UNWRAPPED
  );
  return pool.burnSingle(data, wallet.address, ZERO_ADDRESS, '0x');
}

async function swap(tokenIn: string) {
  const data = defaultAbiCoder.encode(
    ["address", "address", "uint8"], [tokenIn, wallet.address, 1] // 1 = UNWRAPPED
  );
  return pool.swap(data, wallet.address, ZERO_ADDRESS, '0x');
}

async function tryMint(
  token0Amount: BigNumber,
  token1Amount: BigNumber,
  expectedLiquidity?: string,
  expectedFee0?: string,
  expectedFee1?: string
) {
  const poolBalance0Before = await balanceOf(token0, pool);
  const poolBalance1Before = await balanceOf(token1, pool);

  const totalSupplyBefore = await pool.totalSupply();
  const liquidityBefore = await balanceOf(pool, wallet);

  // Prefund tokens.
  await deposit(token0, token0Amount);
  await deposit(token1, token1Amount);
  expect(await balanceOf(token0, pool)).to.eq(token0Amount.add(poolBalance0Before));
  expect(await balanceOf(token1, pool)).to.eq(token1Amount.add(poolBalance1Before));

  const calculated = await calculateLiquidityToMint(
    wallet.address,
    vault,
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

  if (poolBalance0Before.isZero()) {
    await expect(mint())
      .to.emit(pool, 'Transfer')
      .withArgs(ZERO_ADDRESS, ZERO_ADDRESS, MINIMUM_LIQUIDITY)
      .to.emit(pool, 'Transfer')
      .withArgs(ZERO_ADDRESS, wallet.address, calculated.liquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(pool, 'Sync')
      .withArgs(token0Amount, token1Amount)
      .to.emit(pool, 'Mint')
      .withArgs(wallet.address, token0Amount, token1Amount, calculated.liquidity.sub(MINIMUM_LIQUIDITY), wallet.address);
  } else {
    await expect(mint())
      .to.emit(pool, 'Transfer')
      .withArgs(ZERO_ADDRESS, wallet.address, calculated.liquidity)
      .to.emit(pool, 'Sync')
      .withArgs(token0Amount.add(poolBalance0Before), token1Amount.add(poolBalance1Before))
      .to.emit(pool, 'Mint')
      .withArgs(wallet.address, token0Amount, token1Amount, calculated.liquidity, wallet.address);
  }

  expect(await balanceOf(token0, pool)).to.eq(token0Amount.add(poolBalance0Before));
  expect(await balanceOf(token1, pool)).to.eq(token1Amount.add(poolBalance1Before));

  expect(await pool.totalSupply()).to.eq(
    calculated.liquidity.add(totalSupplyBefore).add(calculated.protocolFee) // Add if has protocol fee minted.
  );
  const liquidityAfter = (
    poolBalance0Before.isZero() ?
      calculated.liquidity.sub(MINIMUM_LIQUIDITY) :
      calculated.liquidity.add(liquidityBefore)
  );
  expect(await balanceOf(pool, wallet)).to.eq(liquidityAfter);

  expect(await pool.reserve0()).to.eq(token0Amount.add(poolBalance0Before));
  expect(await pool.reserve1()).to.eq(token1Amount.add(poolBalance1Before));
}

async function tryBurn(
  liquidity: BigNumber,
  expectedAmount0: string,
  expectedAmount1: string
) {
  const liquidityBalance = await balanceOf(pool, wallet);
  const balance0Before = await balanceOf(token0, wallet);
  const balance1Before = await balanceOf(token1, wallet);

  const totalSupply = await pool.totalSupply();
  const poolBalance0 = await balanceOf(token0, pool);
  const poolBalance1 = await balanceOf(token1, pool);

  const expectedToken0Amount = calculatePoolTokens(liquidity, poolBalance0, totalSupply);
  const expectedToken1Amount = calculatePoolTokens(liquidity, poolBalance1, totalSupply);
  expect(expectedToken0Amount).to.eq(expectedAmount0);
  expect(expectedToken1Amount).to.eq(expectedAmount1);

  await pool.transfer(pool.address, liquidity);
  expect(await balanceOf(pool, wallet)).to.eq(liquidityBalance.sub(liquidity));
  expect(await balanceOf(pool, pool)).to.eq(liquidity);

  await expect(burn())
    .to.emit(pool, 'Transfer')
    .withArgs(pool.address, ZERO_ADDRESS, liquidity)
    //.to.emit(token0, 'Transfer')
    //.withArgs(pool.address, wallet.address, expectedToken0Amount)
    //.to.emit(token1, 'Transfer')
    //.withArgs(pool.address, wallet.address, expectedToken1Amount)
    .to.emit(pool, 'Sync')
    .withArgs(poolBalance0.sub(expectedToken0Amount), poolBalance1.sub(expectedToken1Amount))
    .to.emit(pool, 'Burn')
    .withArgs(wallet.address, expectedToken0Amount, expectedToken1Amount, liquidity, wallet.address);

  expect(await balanceOf(pool, pool)).to.eq(0);
  expect(await pool.totalSupply()).to.eq(totalSupply.sub(liquidity));

  expect(await balanceOf(token0, pool)).to.eq(poolBalance0.sub(expectedToken0Amount));
  expect(await balanceOf(token1, pool)).to.eq(poolBalance1.sub(expectedToken1Amount));

  expect(await balanceOf(token0, wallet)).to.eq(balance0Before.add(expectedToken0Amount));
  expect(await balanceOf(token1, wallet)).to.eq(balance1Before.add(expectedToken1Amount));
}

async function tryBurnSingle(
  liquidity: BigNumber,
  tokenOut: string,
  expectedAmount0: string,
  expectedAmount1: string
) {
  const liquidityBalance = await balanceOf(pool, wallet);

  const totalSupply = await pool.totalSupply();
  const poolBalance0 = await balanceOf(token0, pool);
  const poolBalance1 = await balanceOf(token1, pool);

  const token0AmountBalanced = calculatePoolTokens(liquidity, poolBalance0, totalSupply);
  const token1AmountBalanced = calculatePoolTokens(liquidity, poolBalance1, totalSupply);

  const swapFee = await getSwapFee(pool, wallet.address);
  const token0Amount = (
    tokenOut == token0.address ?
      token0AmountBalanced.add(getAmountOut({
        amountIn: token1AmountBalanced,
        reserveIn: poolBalance1.sub(token1AmountBalanced),
        reserveOut: poolBalance0.sub(token0AmountBalanced),
        swapFee: swapFee,
        //tokenInPrecisionMultiplier: await pool.token1PrecisionMultiplier(),
        //tokenOutPrecisionMultiplier: await pool.token0PrecisionMultiplier()
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
        //tokenInPrecisionMultiplier: await pool.token0PrecisionMultiplier(),
        //tokenOutPrecisionMultiplier: await pool.token1PrecisionMultiplier()
      })) :
      ZERO
  );
  expect(token0Amount).to.eq(expectedAmount0);
  expect(token1Amount).to.eq(expectedAmount1);

  await pool.transfer(pool.address, liquidity);
  expect(await balanceOf(pool, wallet)).to.eq(liquidityBalance.sub(liquidity));
  expect(await balanceOf(pool, pool)).to.eq(liquidity);

  //const isToken0Out = tokenOut == token0.address;

  await expect(burnSingle(tokenOut))
    .to.emit(pool, 'Transfer')
    .withArgs(pool.address, ZERO_ADDRESS, liquidity)
    //.to.emit(isToken0Out ? token0 : token1, 'Transfer')
    //.withArgs(pool.address, wallet.address, expectedTokenOutAmount)
    .to.emit(pool, 'Sync')
    .withArgs(poolBalance0.sub(token0Amount), poolBalance1.sub(token1Amount))
    .to.emit(pool, 'Burn')
    .withArgs(wallet.address, token0Amount, token1Amount, liquidity, wallet.address);
}

async function trySwap(
  token0AmountLiquidity: BigNumber,
  token1AmountLiquidity: BigNumber,
  tokenIn: Contract,
  amountIn: BigNumber,
  expectedAmountOut: BigNumber | string
) {
  // Add initial liquidity.
  await tryMint(token0AmountLiquidity, token1AmountLiquidity);

  const poolTokenInBalanceBefore = await balanceOf(tokenIn, pool);
  const isToken0In = tokenIn.address == token0.address;
  const tokenOut = isToken0In ? token1 : token0;
  const poolTokenOutBalanceBefore = await balanceOf(tokenOut, pool);

  // Prefund the pool.
  await deposit(tokenIn, amountIn);
  expect(await balanceOf(tokenIn, pool)).to.eq(poolTokenInBalanceBefore.add(amountIn));

  const [reserve0, reserve1] = [
    await pool.reserve0(),
    await pool.reserve1()
  ];
  const [reserveIn, reserveOut] = (
    isToken0In ? [reserve0, reserve1] : [reserve1, reserve0]
  );

  /*
  const [token0PrecisionMultiplier, token1PrecisionMultiplier] = [
    await pool.token0PrecisionMultiplier(),
    await pool.token1PrecisionMultiplier()
  ];
  const [tokenInPrecisionMultiplier, tokenOutPrecisionMultiplier] = (
    isToken0In ? [token0PrecisionMultiplier, token1PrecisionMultiplier] : [token1PrecisionMultiplier, token0PrecisionMultiplier]
  );
  */

  const amountOut = getAmountOut({
    amountIn: amountIn,
    reserveIn: reserveIn,
    reserveOut: reserveOut,
    swapFee: await getSwapFee(pool, wallet.address),
    //tokenInPrecisionMultiplier: tokenInPrecisionMultiplier,
    //tokenOutPrecisionMultiplier: tokenOutPrecisionMultiplier
  });
  expect(amountOut).to.eq(expectedAmountOut);

  const [amount0Out, amount1Out] = isToken0In ? [0, amountOut] : [amountOut, 0];
  const [amount0In, amount1In] = isToken0In ? [amountIn, 0] : [0, amountIn];

  await expect(swap(tokenIn.address))
    .to.emit(pool, 'Swap')
    .withArgs(wallet.address, amount0In, amount1In, amount0Out, amount1Out, wallet.address);

  expect(await balanceOf(tokenIn, pool)).to.eq(poolTokenInBalanceBefore.add(amountIn));
  expect(await balanceOf(tokenOut, pool)).to.eq(poolTokenOutBalanceBefore.sub(amountOut));
}

describe('Classic Pool', () => {

  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];
  });

  beforeEach(async () => {
    const fixture = await classicPoolFixture(wallet, false, false);
    weth = fixture.weth;
    vault = fixture.vault;
    master = fixture.master;
    factory = fixture.factory;
    token0 = fixture.token0;
    token1 = fixture.token1;
    pool = fixture.pool;
  });

  it("Should returns expected pool metadata", async () => {
    expect(await pool.master()).to.eq(master.address);
    expect(await pool.vault()).to.eq(vault.address);
    expect(await pool.token0()).to.eq(token0.address);
    expect(await pool.token1()).to.eq(token1.address);
    expect(await pool.poolType()).to.eq(1);
    expect(await pool.reserve0()).to.eq(0);
    expect(await pool.reserve1()).to.eq(0);
    expect(await pool.invariantLast()).to.eq(0);
  });

  // Mint liquidity
  it("Should revert on mint liquidity without token", async () => {
    await expect(mint()).to.be.reverted;
  });

  it("Should revert on mint liquidity with only token0", async () => {
    await deposit(token0, 1);
    await expect(mint()).to.be.reverted;

    await deposit(token0, expandTo18Decimals(1));
    await expect(mint()).to.be.reverted;
  });

  it("Should revert on mint liquidity with only token1", async () => {
    await deposit(token1, 1);
    await expect(mint()).to.be.reverted;

    await deposit(token1, expandTo18Decimals(1));
    await expect(mint()).to.be.reverted;
  });

  it("Should revert on mint liquidity (minimal tokens)", async () => {
    await deposit(token0, 1000);
    await deposit(token1, 1000);
    await expect(mint()).to.be.reverted;
  });

  it("Should NOT revert on mint liquidity (minimal tokens)", async () => {
    await deposit(token0, 10000);
    await deposit(token1, 10000);
    await expect(mint()).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq(10000);
  });

  it("Should revert on mint liquidity (maximum tokens)", async () => {
    await deposit(token0, expandTo18Decimals('1000000000000000000000'));
    await deposit(token1, expandTo18Decimals('1000000000000000000000'));
    await expect(mint()).to.be.reverted;
  });

  it("Should NOT revert on mint liquidity (maximum tokens)", async () => {
    await deposit(token0, expandTo18Decimals('100000000000000000000'));
    await deposit(token1, expandTo18Decimals('100000000000000000000'));
    await expect(mint()).to.be.not.reverted;
    expect(await pool.totalSupply()).to.eq('100000000000000000000000000000000000000');
  });

  it("Should mint expected liquidity", async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');
  });

  it("Should mint expected liquidity (evenly)", async () => {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(1);
    await tryMint(token0Amount, token1Amount, '1000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('1000000000000000000');
  });

  it("Should mint expected liquidity (edge case)", async () => {
    const token0Amount = BigNumber.from(1);
    const token1Amount = expandTo18Decimals('10000000');
    await tryMint(token0Amount, token1Amount, '3162277660168', '0', '0');
    expect(await pool.totalSupply()).to.eq('3162277660168');
  });

  it("Should mint expected liquidity balanced", async () => {
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');

    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('4000000000000000000');

    token0Amount = expandTo18Decimals(5);
    token1Amount = expandTo18Decimals(20);
    await tryMint(token0Amount, token1Amount, '10000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('14000000000000000000');
  });

  it("Should mint expected liquidity unbalanced", async () => {
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');
    expect(await pool.totalSupply()).to.eq('2000000000000000000');

    token0Amount = expandTo18Decimals(4);
    token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '4315211208054407211', '4500000000000000', '0');
    expect(await pool.totalSupply()).to.eq('6317456159747988712');

    // Add calculated balanced liquidity expects no fee.
    const reserve0 = await pool.reserve0();
    const reserve1 = await pool.reserve1();
    token0Amount = expandTo18Decimals(1);
    token1Amount = token0Amount.mul(reserve1).div(reserve0);
    expect(token1Amount).to.eq('1600000000000000000');
    await tryMint(token0Amount, token1Amount, '1263491231949597742', '0', '0');
    expect(await pool.totalSupply()).to.eq('7580947391697586454');
  });

  // Burn liquidity
  it("Should burn some liquidity", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    await tryBurn(BigNumber.from(500000), '250000', '1000000');
  });

  it("Should burn some liquidity (edge case)", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    await tryBurn(BigNumber.from(1), '0', '2'); // no token0 received
    await tryBurn(BigNumber.from(10), '5', '20');
  });

  it("Should burn all liquidity", async () => {
    // Add initial liquidity.
    let token0Amount = expandTo18Decimals(1);
    let token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    await tryBurn(liquidity, '999999999999999500', '3999999999999998000');
  });

  it("Should burn some liquidity single for token0", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    await tryBurnSingle(BigNumber.from(500000), token0.address, '499249', '0');
    expect(await pool.balanceOf(wallet.address)).to.eq('1999999999999499000');
  });

  it("Should burn some liquidity single for token1", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    await tryBurnSingle(BigNumber.from(500000), token1.address, '0', '1996999');
    expect(await pool.balanceOf(wallet.address)).to.eq('1999999999999499000');
  });

  it("Should burn all liquidity single for token0", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    // received 999999999999999799 + 200 swapped
    await tryBurnSingle(liquidity, token0.address, '999999999999999999', '0');
    expect(await pool.balanceOf(wallet.address)).to.eq(0);
    expect(await pool.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  it("Should burn all liquidity single for token1", async () => {
    // Add initial liquidity.
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await tryMint(token0Amount, token1Amount, '2000000000000000000', '0', '0');

    const liquidity = await pool.balanceOf(wallet.address);
    expect(liquidity).to.eq('1999999999999999000');

    // received 3999999999999999199 + 800 swapped
    await tryBurnSingle(liquidity, token1.address, '0', '3999999999999999999');
    expect(await pool.balanceOf(wallet.address)).to.eq(0);
    expect(await pool.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  // Swap
  const swapTestCases: BigNumber[][] = [
    // unbalanced
    [1, 4, 1, '1996995493239859789'],
    [4, 1, 1, '199519711827096257'],
    [10, 5, 1, '453305446940074565'],
    [5, 10, 1, '1662497915624478906'],
    [5, 10, 2, '2851015155847869602'],
    [10, 5, 2, '831248957812239453'],
    [1, 100, 1, '49924887330996494742'],
    [100, 1, 1, '9871580343970612'],
    ['1', 1000, 1, '999999999999999998996'],
    [1000, '1', 1, '0'],

    // balanced
    [1, 1, 1, '499248873309964947'],
    [10, 10, 1, '906610893880149131'],
    [100, 100, 1, '987158034397061298'],
    [1000, 1000, 1, '996006981039903216'],

    // zero input
    [10, 5, 0, 0],
    [1000, 1000, 0, 0],
    ['1', 1000, 0, 0],

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

      await trySwap(
        token0AmountLiquidity,
        token1AmountLiquidity,
        token0,
        amountIn,
        amountOut
      );
    });
  });

  swapTestCases.forEach((swapTestCase, i) => {
    it(`Should swap token1 for token0 - case ${i + 1}`, async () => {
      const [token0AmountLiquidity, token1AmountLiquidity, amountIn, amountOut] = swapTestCase;

      await trySwap(
        token1AmountLiquidity,
        token0AmountLiquidity,
        token1,
        amountIn,
        amountOut
      );
    });
  });

});