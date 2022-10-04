import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals } from './shared/utilities';
import { deployTestERC20, factoryFixture } from './shared/fixtures';
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
  let swapFeeProvider: Contract;

  beforeEach(async () => {
    const fixture = await factoryFixture(other.address);
    factory = fixture.factory;
    swapFeeProvider = fixture.swapFeeProvider;
  });

  /*
  it('INIT_CODE_PAIR_HASH', async () => {
    expect(await factory.INIT_CODE_PAIR_HASH()).to.eq('0x0a44d25bd998b8cce3bec356e00044787b55feabe1b89cb62eba44ef25855128')
  })
  */

  it('Should returns default fee recipient', async () => {
    expect(await factory.feeRecipient()).to.eq(other.address);
  });

  it('Should returns default owner', async () => {
    expect(await factory.owner()).to.eq(wallet.address);
  });

  it('Should returns default pool count', async () => {
    expect(await factory.allPairsLength()).to.eq(0);
  });

  it('Should returns default protocol fee', async () => {
    expect(await factory.protocolFee()).to.eq(5);
  });

  it('Should returns default swap fee provider', async () => {
    expect(await factory.swapFeeProvider()).to.eq(swapFeeProvider.address);
  });

  async function createPair(tokenA: string, tokenB: string, stable: boolean) {    
    const [token0, token1]: [string, string] = (
      Number(tokenA) < Number(tokenB) ? [tokenA, tokenB] : [tokenB, tokenA]
    );

    await expect(factory.createPair(tokenA, tokenB, stable))
      .to.emit(factory, 'PairCreated');

    await expect(factory.createPair(tokenA, tokenB, stable)).to.be.reverted; // PAIR_EXISTS
    await expect(factory.createPair(tokenB, tokenA, stable)).to.be.reverted; // PAIR_EXISTS

    const pairAddress = await factory.getPair(tokenA, tokenB, stable);
    expect(await factory.getPair(tokenB, tokenA, stable)).to.eq(pairAddress);
    expect(await factory.getPair(tokenB, tokenA, !stable)).to.eq(ZERO_ADDRESS);
    expect(await factory.isPair(pairAddress)).to.eq(true);
    expect(await factory.allPairs(0)).to.eq(pairAddress);
    expect(await factory.allPairsLength()).to.eq(1);

    const pairArtifact: Artifact = await hre.artifacts.readArtifact('SyncSwapPool');
    const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider);
    expect(await pair.factory()).to.eq(factory.address);
    expect(await pair.token0()).to.eq(token0);
    expect(await pair.token1()).to.eq(token1);
    expect(await pair.stable()).to.eq(stable);
  };

  it('Should create a volatile pool', async () => {
    await createPair(testTokens[0], testTokens[1], false);
  });

  it('Should create a stable pool', async () => {
    await createPair(testTokens[0], testTokens[1], true);
  });

  it('Should create a volatile pool in reverse tokens', async () => {
    await createPair(testTokens[1], testTokens[0], false);
  });

  it('Should create a stable pool in reverse tokens', async () => {
    await createPair(testTokens[1], testTokens[0], true);
  });

  it('Should use expected gas on creating pair', async () => {
    const tx = await factory.createPair(testTokens[0], testTokens[1], false);
    const receipt = await tx.wait();
    expect(receipt.gasUsed).to.eq(2232828); // 2512920 for Uniswap V2
  });

  it('Should set a new fee recipient', async () => {
    await expect(factory.connect(other).setFeeRecipient(other.address)).to.be.reverted;
    await factory.setFeeRecipient(wallet.address);
    expect(await factory.feeRecipient()).to.eq(wallet.address);
  });

  it('Should set a new protocol fee', async () => {
    expect(await factory.protocolFee()).to.eq(5);
    await expect(factory.connect(other).setProtocolFee(6)).to.be.reverted;
    await factory.setProtocolFee(6);
    expect(await factory.protocolFee()).to.eq(6);
  });
});