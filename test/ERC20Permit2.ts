import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals, getPermitSignature, getSplittedPermitSignature, MAX_UINT256 } from './shared/utilities';
import { hexlify } from 'ethers/lib/utils';
import { deployERC20Permit2 } from './shared/fixtures';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

chai.use(solidity)

const hre = require('hardhat');

const TOTAL_SUPPLY = expandTo18Decimals(10000);
const TEST_AMOUNT = expandTo18Decimals(10);

describe('ERC20Permit2', () => {
  let wallet: SignerWithAddress;
  let other: SignerWithAddress;
  before(async () => {
    const accounts = await hre.ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];
  })

  let token: Contract;
  beforeEach(async () => {
    token = await deployERC20Permit2(TOTAL_SUPPLY);
  })

  it('Should return expected token metadata', async () => {
    expect(await token.name()).to.eq('');
    expect(await token.symbol()).to.eq('');
    expect(await token.decimals()).to.eq(18);
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY);
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY);
  })

  it('Should approve some tokens', async () => {
    await expect(token.approve(other.address, TEST_AMOUNT))
      .to.emit(token, 'Approval')
      .withArgs(wallet.address, other.address, TEST_AMOUNT);

    expect(await token.allowance(wallet.address, other.address)).to.eq(TEST_AMOUNT);
  })

  it('Should transfer some tokens', async () => {
    await expect(token.transfer(other.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, other.address, TEST_AMOUNT);

    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT));
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT);
  })

  it('Should fail to transfer tokens', async () => {
    await expect(token.transfer(other.address, TOTAL_SUPPLY.add(1))).to.be.reverted; // undeflow
    await expect(token.connect(other).transfer(wallet.address, 1)).to.be.reverted; // overflow
  })

  it('Should transfer some tokens from other wallet', async () => {
    await token.approve(other.address, TEST_AMOUNT);
    
    await expect(token.connect(other).transferFrom(wallet.address, other.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, other.address, TEST_AMOUNT);

    expect(await token.allowance(wallet.address, other.address)).to.eq(0);
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT));
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT);
  })

  it('Should transfer all tokens from other wallet', async () => {
    await token.approve(other.address, MAX_UINT256);

    await expect(token.connect(other).transferFrom(wallet.address, other.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, other.address, TEST_AMOUNT);

    expect(await token.allowance(wallet.address, other.address)).to.eq(MAX_UINT256);
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT));
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT);
  })

  it('Should permit some tokens by splitted signature', async () => {
    const nonce = await token.nonces(wallet.address);
    const deadline = MAX_UINT256;

    const { v, r, s } = await getSplittedPermitSignature(
      wallet,
      token,
      { owner: wallet.address, spender: other.address, value: TEST_AMOUNT },
      nonce,
      deadline
    );

    await expect(token.permit(wallet.address, other.address, TEST_AMOUNT, deadline, v, hexlify(r), hexlify(s)))
      .to.emit(token, 'Approval')
      .withArgs(wallet.address, other.address, TEST_AMOUNT);

    expect(await token.allowance(wallet.address, other.address)).to.eq(TEST_AMOUNT);
    expect(await token.nonces(wallet.address)).to.eq(BigNumber.from(1));
  })

  it('Should permit some tokens by array signature', async () => {
    const nonce = await token.nonces(wallet.address);
    const deadline = MAX_UINT256;

    const signature = await getPermitSignature(
      wallet,
      token,
      { owner: wallet.address, spender: other.address, value: TEST_AMOUNT },
      nonce,
      deadline
    );

    await expect(token.permit2(wallet.address, other.address, TEST_AMOUNT, deadline, signature))
      .to.emit(token, 'Approval')
      .withArgs(wallet.address, other.address, TEST_AMOUNT);

    expect(await token.allowance(wallet.address, other.address)).to.eq(TEST_AMOUNT);
    expect(await token.nonces(wallet.address)).to.eq(BigNumber.from(1));
  })
})