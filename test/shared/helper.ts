import { BigNumber, Contract } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ZERO, ZERO_ADDRESS } from "./utilities";

const hre: HardhatRuntimeEnvironment = require("hardhat");

const ONE = BigNumber.from(1);
const TWO = BigNumber.from(2);
const MAX_LOOP_LIMIT = 256;

function sqrt(value: BigNumber): BigNumber {
  const x = BigNumber.from(value);
  let z = x.add(ONE).div(TWO);
  let y = x;
  while (z.sub(y).isNegative()) {
    y = z;
    z = x.div(z).add(z).div(TWO);
  }
  return y;
}

const STABLE_A = BigNumber.from(1000);

async function computeInvariant(
  pool: Contract,
  balance0: BigNumber,
  balance1: BigNumber
): Promise<BigNumber> {
  const poolType = await pool.poolType();
  if (poolType == 1) {
    return sqrt(balance0.mul(balance1));
  } else {
    const adjustedReserve0 = balance0.mul(await pool.token0PrecisionMultiplier());
    const adjustedReserve1 = balance1.mul(await pool.token1PrecisionMultiplier());
    return computeDFromAdjustedBalances(STABLE_A, adjustedReserve0, adjustedReserve1);
  }
}

function computeDFromAdjustedBalances(
  A: BigNumber,
  xp0: BigNumber,
  xp1: BigNumber
): BigNumber {
  const s = xp0.add(xp1);

  if (s.isZero()) {
    return ZERO;
  } else {
    let prevD;
    let d = s;
    const nA = A.mul(2);
    for (let i = 0; i < MAX_LOOP_LIMIT; i++) {
      const dP = d.mul(d).div(xp0).mul(d).div(xp1).div(4);
      prevD = d;
      d = nA.mul(s).add(dP.mul(2)).mul(d).div(
        nA.sub(1).mul(d).add(dP.mul(3))
      );
      if (within1(d, prevD)) {
        return d;
      }
    }
    return d;
  }
}

function within1(a: BigNumber, b: BigNumber): boolean {
  if (a.gt(b)) {
    return a.sub(b).lte(1);
  } else {
    return b.sub(a).lte(1);
  }
}

const MAX_FEE = BigNumber.from(100000); // 1e5

function unbalancedMintFee(
  swapFee: BigNumber,
  reserve0: BigNumber,
  reserve1: BigNumber,
  amount0: BigNumber,
  amount1: BigNumber
): [BigNumber, BigNumber] {
  if (reserve0.isZero() || reserve1.isZero()) {
    return [ZERO, ZERO];
  }
  const amount1Optimal = amount0.mul(reserve1).div(reserve0);
  if (amount1.gte(amount1Optimal)) {
    return [
      ZERO,
      swapFee.mul(amount1.sub(amount1Optimal)).div(MAX_FEE.mul(2))
    ];
  } else {
    const amount0Optimal = amount1.mul(reserve0).div(reserve1);
    return [
      swapFee.mul(amount0.sub(amount0Optimal)).div(MAX_FEE.mul(2)),
      ZERO
    ];
  }
}

async function calculateMintProtocolFee(
  pool: Contract,
  reserve0: BigNumber,
  reserve1: BigNumber
): Promise<{
  totalSupply: BigNumber,
  invariant: BigNumber,
  protocolFee: BigNumber
}> {
  const totalSupply = await pool.totalSupply();
  const invariant = await computeInvariant(pool, reserve0, reserve1);

  const master = await getPoolMaster(await pool.master());
  const feeTo = await master.getFeeRecipient();

  if (feeTo == ZERO_ADDRESS) {
    return {
      totalSupply,
      invariant,
      protocolFee: ZERO
    };
  }

  const lastInvariant = await pool.invariantLast();
  if (!lastInvariant.isZero()) {
    if (invariant.gt(lastInvariant)) {
      const protocolFee = BigNumber.from(await master.getProtocolFee(pool.address));
      const numerator = totalSupply.mul(invariant.sub(lastInvariant)).mul(protocolFee);
      const denominator = MAX_FEE.sub(protocolFee).mul(invariant).add(protocolFee.mul(lastInvariant));
      const liquidity = numerator.div(denominator);
      return {
        totalSupply: totalSupply.add(liquidity),
        invariant,
        protocolFee: liquidity
      };
    }
  }

  return {
    totalSupply,
    invariant,
    protocolFee: ZERO
  };
}

async function getBasePoolFactory(factoryAddress: string): Promise<Contract> {
  const artifact = await hre.artifacts.readArtifact('IBasePoolFactory');
  return new Contract(factoryAddress, artifact.abi, hre.ethers.provider);
}

async function getPoolMaster(factoryAddress: string): Promise<Contract> {
  const artifact = await hre.artifacts.readArtifact('IPoolMaster');
  return new Contract(factoryAddress, artifact.abi, hre.ethers.provider);
}

async function getToken(tokenAddress: string): Promise<Contract> {
  const tokenArtifact = await hre.artifacts.readArtifact('TestERC20');
  return new Contract(tokenAddress, tokenArtifact.abi, hre.ethers.provider);
}

export async function getSwapFee(pool: Contract, sender: string): Promise<BigNumber> {
  const master = await getPoolMaster(await pool.master());
  return BigNumber.from(await master.getSwapFee(pool.address, sender, ZERO_ADDRESS, ZERO_ADDRESS, "0x"));
}

export async function calculateLiquidityToMint(
  sender: string,
  vault: Contract,
  pool: Contract,
  amount0In: BigNumber,
  amount1In: BigNumber
): Promise<{
  liquidity: BigNumber,
  fee0: BigNumber,
  fee1: BigNumber,
  protocolFee: BigNumber
}> {
  let reserve0 = await pool.reserve0();
  let reserve1 = await pool.reserve1();

  const token0 = await getToken(await pool.token0());
  const token1 = await getToken(await pool.token1());
  const balance0 = await vault.balanceOf(token0.address, pool.address);
  const balance1 = await vault.balanceOf(token1.address, pool.address);

  const newInvariant = await computeInvariant(pool, balance0, balance1);
  const swapFee = await getSwapFee(pool, sender);

  const [fee0, fee1] = unbalancedMintFee(swapFee, reserve0, reserve1, amount0In, amount1In);

  // Add unbalanced fees.
  const calculated = await calculateMintProtocolFee(pool, reserve0.add(fee0), reserve1.add(fee1));

  if (calculated.totalSupply.isZero()) {
    return {
      liquidity: newInvariant,
      fee0,
      fee1,
      protocolFee: ZERO
    };
  } else {
    const oldInvariant = calculated.invariant;
    return {
      liquidity: newInvariant.sub(oldInvariant).mul(calculated.totalSupply).div(oldInvariant),
      fee0,
      fee1,
      protocolFee: calculated.protocolFee
    };
  }
}

export function calculatePoolTokens(
  liquidity: BigNumber,
  balance: BigNumber,
  totalSupply: BigNumber
): BigNumber {
  return liquidity.mul(balance).div(totalSupply);
}

interface GetAmountOutParams {
  amountIn: BigNumber,
  reserveIn: BigNumber;
  reserveOut: BigNumber;
  swapFee: BigNumber;
  A?: BigNumber;
  tokenInPrecisionMultiplier?: BigNumber;
  tokenOutPrecisionMultiplier?: BigNumber;
}

function getY(A: BigNumber, x: BigNumber, d: BigNumber): BigNumber {
  let c = d.mul(d).div(x.mul(2));
  const nA = A.mul(2);
  c = c.mul(d).div(nA.mul(2));
  const b = x.add(d.div(nA));
  let yPrev;
  let y = d;
  for (let i = 0; i < MAX_LOOP_LIMIT; i++) {
    yPrev = y;
    y = y.mul(y).add(c).div(y.mul(2).add(b).sub(d));
    if (within1(y, yPrev)) {
      break;
    }
  }
  return y;
}

function getAmountOutClassic(params: GetAmountOutParams): BigNumber {
  const amountInWithFee = params.amountIn.mul(MAX_FEE.sub(params.swapFee));
  return amountInWithFee.mul(params.reserveOut).div(params.reserveIn.mul(MAX_FEE).add(amountInWithFee));
}

function getAmountOutStable(params: GetAmountOutParams): BigNumber {
  const adjustedReserveIn = params.reserveIn.mul(params.tokenInPrecisionMultiplier!);
  const adjustedReserveOut = params.reserveOut.mul(params.tokenOutPrecisionMultiplier!);
  const feeDeductedAmountIn = params.amountIn.sub(params.amountIn.mul(params.swapFee).div(MAX_FEE));
  const d = computeDFromAdjustedBalances(params.A!, adjustedReserveIn, adjustedReserveOut);

  const x = adjustedReserveIn.add(feeDeductedAmountIn.mul(params.tokenInPrecisionMultiplier!));
  const y = getY(params.A!, x, d);
  const dy = adjustedReserveOut.sub(y).sub(1);
  return dy.div(params.tokenOutPrecisionMultiplier!);
}

export function getAmountOut(params: GetAmountOutParams): BigNumber {
  if (params.amountIn.isZero()) {
    return ZERO;
  } else {
    if (params.A && !params.A.isZero()) {
      return getAmountOutStable(params);
    } else {
      return getAmountOutClassic(params);
    }
  }
}