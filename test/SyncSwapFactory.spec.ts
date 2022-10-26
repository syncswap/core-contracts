import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals } from './shared/utilities';
import { deployFactory, deployTestERC20 } from './shared/fixtures';
import { Artifact, HardhatRuntimeEnvironment } from 'hardhat/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ZERO_ADDRESS } from './shared/utilities';

const hre: HardhatRuntimeEnvironment = require('hardhat');
const ethers = require("hardhat").ethers;
chai.use(solidity);

describe('SyncSwapFactory', () => {
  let wallet: SignerWithAddress;
  let other: SignerWithAddress;
  let testTokens: [string, string];

  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];

    const tokenA = await deployTestERC20(expandTo18Decimals(10000));
    const tokenB = await deployTestERC20(expandTo18Decimals(10000));
    testTokens = [tokenA.address, tokenB.address];
  });

  let factory: Contract;

  beforeEach(async () => {
    factory = await deployFactory(other.address);
  });

  /*
  it('INIT_CODE_PAIR_HASH', async () => {
    expect(await factory.INIT_CODE_PAIR_HASH()).to.eq('0x0a44d25bd998b8cce3bec356e00044787b55feabe1b89cb62eba44ef25855128')
  })
  */

  it('Should return default values', async () => {
    expect(await factory.feeRecipient()).to.eq(other.address);
    expect(await factory.owner()).to.eq(wallet.address);
    expect(await factory.allPoolsLength()).to.eq(0);
    expect(await factory.protocolFee()).to.eq(30000);
    expect(await factory.defaultSwapFeeVolatile()).to.eq(300);
    expect(await factory.defaultSwapFeeStable()).to.eq(100);
  });

  async function createPool(tokenA: string, tokenB: string, stable: boolean) {
    const [token0, token1]: [string, string] = (
      Number(tokenA) < Number(tokenB) ? [tokenA, tokenB] : [tokenB, tokenA]
    );

    await expect(factory.createPool(tokenA, tokenB, stable))
      .to.emit(factory, 'PoolCreated');

    await expect(factory.createPool(tokenA, tokenB, stable)).to.be.reverted; // PAIR_EXISTS
    await expect(factory.createPool(tokenB, tokenA, stable)).to.be.reverted; // PAIR_EXISTS

    const pairAddress = await factory.getPool(tokenA, tokenB, stable);
    expect(await factory.getPool(tokenB, tokenA, stable)).to.eq(pairAddress);
    expect(await factory.getPool(tokenB, tokenA, !stable)).to.eq(ZERO_ADDRESS);
    expect(await factory.isPool(pairAddress)).to.eq(true);
    expect(await factory.allPools(0)).to.eq(pairAddress);
    expect(await factory.allPoolsLength()).to.eq(1);

    const pairArtifact: Artifact = await hre.artifacts.readArtifact('SyncSwapPool');
    const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider);
    expect(await pair.factory()).to.eq(factory.address);
    expect(await pair.token0()).to.eq(token0);
    expect(await pair.token1()).to.eq(token1);
    expect(await pair.A()).to.eq(stable ? '400000' : 0);
  };

  it('Should create a volatile pool', async () => {
    await createPool(testTokens[0], testTokens[1], false);
  });

  it('Should create a stable pool', async () => {
    await createPool(testTokens[0], testTokens[1], true);
  });

  it('Should create a volatile pool in reverse tokens', async () => {
    await createPool(testTokens[1], testTokens[0], false);
  });

  it('Should create a stable pool in reverse tokens', async () => {
    await createPool(testTokens[1], testTokens[0], true);
  });

  it('Should use expected gas on creating pair', async () => {
    const tx = await factory.createPool(testTokens[0], testTokens[1], false);
    const receipt = await tx.wait();
    expect(receipt.gasUsed).to.eq(2767452); // 2512920 for Uniswap V2
  });

  it('Should set a new fee recipient', async () => {
    // Set fee recipient using a wrong account.
    await expect(factory.connect(other).setFeeRecipient(other.address)).to.be.reverted;

    // Set a new fee recipient.
    await factory.setFeeRecipient(wallet.address);

    // Expect new fee recipient.
    expect(await factory.feeRecipient()).to.eq(wallet.address);
  });

  it('Should set a new protocol fee', async () => {
    // Expect current protocol fee.
    expect(await factory.protocolFee()).to.eq(30000);

    // Set protocol fee using wrong account.
    await expect(factory.connect(other).setProtocolFee(50000)).to.be.reverted;

    // Set a new protocol fee.
    await factory.setProtocolFee(50000);

    // Expect new protocol fee.
    expect(await factory.protocolFee()).to.eq(50000);
  });
});