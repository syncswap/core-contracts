import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { defaultAbiCoder } from 'ethers/lib/utils';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expandTo18Decimals, MAX_UINT256, ZERO_ADDRESS } from './shared/utilities';
import { routerFixture } from './shared/fixtures';

chai.use(solidity);
const ethers: HardhatEthersHelpers = require('hardhat').ethers;

let wallet: SignerWithAddress;
let token0: Contract;
let token1: Contract;
let router: Contract;
let pair: Contract;

function mintData(): string {
  return defaultAbiCoder.encode(['address'], [wallet.address]);
}

function burnData(): string {
  return defaultAbiCoder.encode(['address', 'uint8'], [wallet.address, 1]);
}

function swapData(tokenIn: string): string {
  return defaultAbiCoder.encode(
    ['address', 'address', 'uint8'],
    [tokenIn, wallet.address, 1]
  );
}

async function addLiquidity(amount: BigNumber): Promise<void> {
  await token0.approve(router.address, amount);
  await token1.approve(router.address, amount);
  await router.addLiquidity(
    pair.address,
    [[token0.address, amount], [token1.address, amount]],
    mintData(),
    0,
    ZERO_ADDRESS,
    '0x'
  );
}

describe('SyncSwapRouter', () => {
  beforeEach(async () => {
    [wallet] = await ethers.getSigners();
    ({ token0, token1, router, pair } = await routerFixture());
  });

  it('adds liquidity through the router', async () => {
    await addLiquidity(expandTo18Decimals(1000));

    expect(await pair.balanceOf(wallet.address)).to.be.gt(0);
  });

  it('swaps through the router and returns the output token amount', async () => {
    await addLiquidity(expandTo18Decimals(1000));

    const amountIn = expandTo18Decimals(10);
    await token0.approve(router.address, amountIn);
    const path = [[
      [[pair.address, swapData(token0.address), ZERO_ADDRESS, '0x']],
      token0.address,
      amountIn
    ]];
    const balanceBefore = await token1.balanceOf(wallet.address);
    const result = await router.callStatic.swap(path, 1, MAX_UINT256);

    await router.swap(path, 1, MAX_UINT256);

    expect(result.token).to.eq(token1.address);
    expect(result.amount).to.be.gt(0);
    expect(await token1.balanceOf(wallet.address)).to.be.gt(balanceBefore);
  });

  it('burns liquidity through the router', async () => {
    await addLiquidity(expandTo18Decimals(1000));

    const liquidity = await pair.balanceOf(wallet.address);
    await pair.approve(router.address, liquidity);
    const token0Before = await token0.balanceOf(wallet.address);
    const token1Before = await token1.balanceOf(wallet.address);

    await router.burnLiquidity(
      pair.address,
      liquidity,
      burnData(),
      [0, 0],
      ZERO_ADDRESS,
      '0x'
    );

    expect(await token0.balanceOf(wallet.address)).to.be.gt(token0Before);
    expect(await token1.balanceOf(wallet.address)).to.be.gt(token1Before);
    expect(await pair.balanceOf(wallet.address)).to.eq(0);
  });
});
