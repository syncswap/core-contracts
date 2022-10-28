import { BigNumber, Contract } from 'ethers';
import { expandTo18Decimals, MAX_UINT256, ZERO_ADDRESS } from './utilities';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const hre: HardhatRuntimeEnvironment = require("hardhat");
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

export async function deployVault(weth: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapVault');
    const contract = await contractFactory.deploy(weth);
    await contract.deployed();
    return contract;
}

export async function deployConstantProductPoolFactory(vault: string, feeRecipient: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('ConstantProductPoolFactory');
    const contract = await contractFactory.deploy(vault, feeRecipient);
    await contract.deployed();
    return contract;
}

export async function deployStablePoolFactory(vault: string, feeRecipient: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('StablePoolFactory');
    const contract = await contractFactory.deploy(vault, feeRecipient);
    await contract.deployed();
    return contract;
}

export async function deploySyncSwapLPToken(totalSupply: BigNumber): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('TestSyncSwapLPToken');
    const contract = await contractFactory.deploy(totalSupply);
    await contract.deployed();
    return contract;
}

interface PoolFixture {
    weth: Contract;
    vault: Contract;
    factory: Contract;
    token0: Contract;
    token1: Contract;
    pool: Contract;
}

export async function constantProductPoolFixture(
    wallet: SignerWithAddress,
    feeRecipient: string
): Promise<PoolFixture> {
    const weth = await deployWETH9();
    const vault = await deployVault(weth.address);
    const factory = await deployConstantProductPoolFactory(vault.address, feeRecipient);

    const tokenA = await deploySyncSwapLPToken(MAX_UINT256);
    const tokenB = await deploySyncSwapLPToken(MAX_UINT256);

    await factory.createPool(tokenA.address, tokenB.address);

    const poolArtifact = await hre.artifacts.readArtifact('ConstantProductPool');
    const poolAddress = await factory.getPool(tokenA.address, tokenB.address);
    const pool = new Contract(poolAddress, poolArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    return { weth, vault, factory, token0, token1, pool };
}

export async function stablePoolFixture(
    wallet: SignerWithAddress,
    feeRecipient: string
): Promise<PoolFixture> {
    const weth = await deployWETH9();
    const vault = await deployVault(weth.address);
    const factory = await deployStablePoolFactory(vault.address, feeRecipient);

    const tokenA = await deploySyncSwapLPToken(MAX_UINT256);
    const tokenB = await deploySyncSwapLPToken(MAX_UINT256);

    await factory.createPool(tokenA.address, tokenB.address);

    const poolArtifact = await hre.artifacts.readArtifact('StablePool');
    const poolAddress = await factory.getPool(tokenA.address, tokenB.address);
    const pool = new Contract(poolAddress, poolArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    return { weth, vault, factory, token0, token1, pool };
}

interface V2Fixture {
    token0: Contract;
    token1: Contract;
    WETH: Contract;
    WETHPartner: Contract;
    factory: Contract;
    router: Contract;
    routerEventEmitter: Contract;
    pair: Contract;
    WETHPair: Contract;
}

export async function deployTestERC20(totalSupply: BigNumber): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('TestERC20');
    const contract = await contractFactory.deploy(totalSupply);
    await contract.deployed();
    return contract;
}

export async function deployDeflatingERC20(totalSupply: BigNumber): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('DeflatingERC20');
    const contract = await contractFactory.deploy(totalSupply);
    await contract.deployed();
    return contract;
}

export async function deployWETH9(): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('TestWETH9');
    const contract = await contractFactory.deploy();
    await contract.deployed();
    return contract;
}

export async function deployRouter(factory: string, WETH: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapRouter');
    const contract = await contractFactory.deploy(factory, WETH);
    await contract.deployed();
    return contract;
}

export async function deployRouterEventEmitter(factory: string, WETH: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('RouterEventEmitter');
    const contract = await contractFactory.deploy(factory, WETH);
    await contract.deployed();
    return contract;
}

export async function v2Fixture(): Promise<V2Fixture> {
    const accounts = await ethers.getSigners()
    const wallet = accounts[0];

    // deploy tokens
    const tokenA = await deployTestERC20(expandTo18Decimals(10000));
    const tokenB = await deployTestERC20(expandTo18Decimals(10000));
    const WETH = await deployWETH9();
    const WETHPartner = await deployTestERC20(expandTo18Decimals(10000));

    // deploy V2
    const vault = await deployVault(WETH.address);
    const { factory } = await deployConstantProductPoolFactory(vault.address, accounts[1].address);

    // deploy routers
    const router = await deployRouter(factory.address, WETH.address);

    // event emitter for testing
    const routerEventEmitter = await deployRouterEventEmitter(factory.address, WETH.address);

    // initialize
    await factory.createPool(tokenA.address, tokenB.address, false);
    const pairAddress = await factory.getPool(tokenA.address, tokenB.address, false);
    const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPool');;
    const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    await factory.createPool(WETH.address, WETHPartner.address, false);
    const WETHPairAddress = await factory.getPool(WETH.address, WETHPartner.address, false);
    const WETHPair = new Contract(WETHPairAddress, pairArtifact.abi, ethers.provider).connect(wallet);

    return {
        token0,
        token1,
        WETH,
        WETHPartner,
        factory,
        router,
        routerEventEmitter,
        pair,
        WETHPair
    };
}