import { BigNumber, Contract } from 'ethers';
import { expandTo18Decimals, ZERO_ADDRESS } from './utilities';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const hre: HardhatRuntimeEnvironment = require("hardhat");
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

export async function deployFactory(feeRecipient: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapFactory');
    const contract = await contractFactory.deploy(feeRecipient);
    await contract.deployed();
    return contract;
}

export async function deploySyncSwapLPToken(totalSupply: BigNumber): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('TestSyncSwapLPToken');
    const contract = await contractFactory.deploy(totalSupply);
    await contract.deployed();
    return contract;
}

interface PairFixture {
    factory: Contract;
    token0: Contract;
    token1: Contract;
    volatilePair: Contract;
    stablePair: Contract;
}

export async function pairFixture(wallet: SignerWithAddress, feeRecipient: SignerWithAddress): Promise<PairFixture> {
    const factory = await deployFactory(feeRecipient.address);

    const tokenA = await deploySyncSwapLPToken(expandTo18Decimals('100000000000000000000'));
    const tokenB = await deploySyncSwapLPToken(expandTo18Decimals('100000000000000000000'));

    await factory.createPool(tokenA.address, tokenB.address, true);
    await factory.createPool(tokenA.address, tokenB.address, false);

    const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPool');

    const stablePairAddress = await factory.getPool(tokenA.address, tokenB.address, true);
    const stablePair = new Contract(stablePairAddress, pairArtifact.abi, ethers.provider).connect(wallet);

    const volatilePairAddress = await factory.getPool(tokenA.address, tokenB.address, false);
    const volatilePair = new Contract(volatilePairAddress, pairArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    return { factory, token0, token1, stablePair, volatilePair };
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
    const { factory } = await deployFactory(accounts[1].address);

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