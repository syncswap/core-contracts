import chai, { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import { expandTo18Decimals, ZERO, ZERO_ADDRESS } from './shared/utilities';
import { deployERC20Permit2, deployVault, deployWETH9 } from './shared/fixtures';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';

chai.use(solidity);

const hre = require('hardhat');
const ethers: HardhatEthersHelpers = hre.ethers;

const TOTAL_SUPPLY = expandTo18Decimals(10000);
const TEST_AMOUNT = expandTo18Decimals(10);
const NATIVE_ETH = ZERO_ADDRESS;

describe('SyncSwapVault', () => {
  let wallet: SignerWithAddress;
  let other: SignerWithAddress;
  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0];
    other = accounts[1];
  })

  let token: Contract;
  let weth: Contract;
  let vault: Contract;
  beforeEach(async () => {
    weth = await deployWETH9();
    vault = await deployVault(weth.address);
    token = await deployERC20Permit2(TOTAL_SUPPLY);
  })

  it('Should deposit some ERC20 tokens', async () => {
    await token.transfer(vault.address, TEST_AMOUNT);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(0);

    await vault.deposit(token.address, wallet.address);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT);
  });

  it('Should receive and deposit some ERC20 tokens', async () => {
    expect(vault.transferAndDeposit(token.address, wallet.address, TEST_AMOUNT))
      .to.be.revertedWith('TransferFromFailed()');

    const balanceBefore = await token.balanceOf(wallet.address);

    await token.approve(vault.address, TEST_AMOUNT);
    await vault.transferAndDeposit(token.address, wallet.address, TEST_AMOUNT);

    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT);
    expect(await token.balanceOf(wallet.address)).to.eq(balanceBefore.sub(TEST_AMOUNT));

    expect(vault.transferAndDeposit(token.address, wallet.address, '1'))
      .to.be.revertedWith('TransferFromFailed()');
  });

  it('Should deposit some ETH', async () => {
    await vault.deposit(NATIVE_ETH, wallet.address, {
      value: TEST_AMOUNT,
    });
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT);
  });

  it('Should deposit some ETH via receive', async () => {
    await wallet.sendTransaction({
      to: vault.address,
      value: TEST_AMOUNT,
    });
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT);
  });

  it('Should deposit some wETH', async () => {
    // Wrap ETH to wETH.
    await weth.deposit({
      value: TEST_AMOUNT,
    });

    await weth.transfer(vault.address, TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(0);

    await vault.deposit(weth.address, wallet.address);
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT);
  });

  it('Should receive and deposit some wETH', async () => {
    // Wrap ETH to wETH.
    await weth.deposit({
      value: TEST_AMOUNT,
    });

    await weth.approve(vault.address, TEST_AMOUNT);
    await vault.transferAndDeposit(weth.address, wallet.address, TEST_AMOUNT);

    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT);
  });

  it('Should transfer some ERC20 tokens', async () => {
    // Deposit tokens.
    await token.transfer(vault.address, TEST_AMOUNT);
    await vault.deposit(token.address, wallet.address);

    expect(vault.connect(other).transfer(token.address, other.address, 1)).to.be.reverted;

    await vault.connect(wallet).transfer(token.address, other.address, 10000);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await vault.balanceOf(token.address, other.address)).to.eq(10000);
  });

  it('Should transfer all ERC20 tokens', async () => {
    // Deposit tokens.
    await token.transfer(vault.address, TEST_AMOUNT);
    await vault.deposit(token.address, wallet.address);

    expect(vault.transfer(token.address, other.address, TEST_AMOUNT.add(1))).to.be.reverted;
    expect(vault.connect(other).transfer(token.address, other.address, TEST_AMOUNT)).to.be.reverted;

    await vault.connect(wallet).transfer(token.address, other.address, TEST_AMOUNT);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(token.address, other.address)).to.eq(TEST_AMOUNT);
  });
  
  it('Should transfer zero ERC20 tokens', async () => {
    expect(vault.transfer(token.address, other.address, 0)).to.be.not.reverted;
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(token.address, other.address)).to.eq(0);

    // Deposit tokens.
    await token.transfer(vault.address, TEST_AMOUNT);
    await vault.deposit(token.address, wallet.address);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT);

    expect(vault.transfer(token.address, other.address, 0)).to.be.not.reverted;
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT);
    expect(await vault.balanceOf(token.address, other.address)).to.eq(0);
  });

  it('Should transfer some ETH', async () => {
    // Deposit ETH.
    await vault.deposit(NATIVE_ETH, wallet.address, {
      value: TEST_AMOUNT,
    });

    await vault.transfer(NATIVE_ETH, other.address, 10000);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await vault.balanceOf(weth.address, other.address)).to.eq(10000);
    expect(await vault.balanceOf(NATIVE_ETH, other.address)).to.eq(10000);

    await vault.connect(wallet).transfer(weth.address, other.address, 10000);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT.sub(20000));
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT.sub(20000));
    expect(await vault.balanceOf(weth.address, other.address)).to.eq(20000);
    expect(await vault.balanceOf(NATIVE_ETH, other.address)).to.eq(20000);
  });

  it('Should transfer all ETH', async () => {
    // Deposit ETH.
    await vault.deposit(NATIVE_ETH, wallet.address, {
      value: TEST_AMOUNT,
    });

    await vault.transfer(NATIVE_ETH, other.address, TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(weth.address, other.address)).to.eq(TEST_AMOUNT);
    expect(await vault.balanceOf(NATIVE_ETH, other.address)).to.eq(TEST_AMOUNT);

    // Deposit wETH.
    await weth.deposit({
      value: TEST_AMOUNT,
    });
    await weth.transfer(vault.address, TEST_AMOUNT);
    await vault.deposit(weth.address, wallet.address);

    await vault.connect(wallet).transfer(weth.address, other.address, TEST_AMOUNT);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(weth.address, other.address)).to.eq(TEST_AMOUNT.add(TEST_AMOUNT));
    expect(await vault.balanceOf(NATIVE_ETH, other.address)).to.eq(TEST_AMOUNT.add(TEST_AMOUNT));
  });

  it('Should withdraw some ERC20 tokens', async () => {
    // Deposit tokens.
    await token.transfer(vault.address, TEST_AMOUNT);
    await vault.deposit(token.address, wallet.address);

    const balanceBefore = await token.balanceOf(wallet.address);

    await vault.withdraw(token.address, wallet.address, 10000);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await token.balanceOf(wallet.address)).to.eq(balanceBefore.add(10000));

    await vault.withdraw(token.address, other.address, 10000);
    expect(await vault.balanceOf(token.address, wallet.address)).to.eq(TEST_AMOUNT.sub(20000));
    expect(await vault.balanceOf(token.address, other.address)).to.eq(0);
    expect(await token.balanceOf(other.address)).to.eq(10000);
  });

  async function getGasFees(response: any): Promise<BigNumber> {
    const receipt = await response.wait();
    return receipt.gasUsed.mul(receipt.effectiveGasPrice);
  }

  it('Should withdraw some ETH', async () => {
    // Deposit ETH.
    await vault.deposit(NATIVE_ETH, wallet.address, {
      value: TEST_AMOUNT,
    });

    const balanceBefore = await wallet.getBalance();

    let fees = ZERO;
    fees = fees.add(await getGasFees(await vault.withdraw(NATIVE_ETH, wallet.address, TEST_AMOUNT)));
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(0);
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(0);
    expect(await wallet.getBalance()).to.eq(balanceBefore.add(TEST_AMOUNT).sub(fees));

    // Deposit wETH.
    fees = fees.add(await getGasFees(await weth.deposit({
      value: 20000,
    })));
    fees = fees.add(await getGasFees(await weth.transfer(vault.address, 20000)));
    fees = fees.add(await getGasFees(await vault.deposit(weth.address, wallet.address)));

    fees = fees.add(await getGasFees(await vault.withdraw(NATIVE_ETH, wallet.address, 10000)));
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(10000);
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(10000);
    expect(await wallet.getBalance()).to.eq(balanceBefore.add(TEST_AMOUNT).sub(10000).sub(fees));
  });

  it('Should withdraw some wETH', async () => {
    // Deposit ETH.
    await vault.deposit(NATIVE_ETH, wallet.address, {
      value: TEST_AMOUNT,
    });

    await vault.withdraw(weth.address, wallet.address, 10000);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await weth.balanceOf(wallet.address)).to.eq(10000);

    // Deposit wETH.
    await weth.deposit({
      value: 10000,
    });
    await weth.transfer(vault.address, 10000);
    await vault.deposit(weth.address, wallet.address);

    await vault.withdraw(weth.address, wallet.address, 10000);
    expect(await vault.balanceOf(weth.address, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await vault.balanceOf(NATIVE_ETH, wallet.address)).to.eq(TEST_AMOUNT.sub(10000));
    expect(await weth.balanceOf(wallet.address)).to.eq(20000);
  });

});