import { BigNumber, Contract } from 'ethers';
import { expandTo18Decimals, MAX_UINT256, ZERO, ZERO_ADDRESS } from './utilities';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { defaultAbiCoder } from 'ethers/lib/utils';

const hre: HardhatRuntimeEnvironment = require("hardhat");
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

export async function deployVault(weth: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapVault');
    const contract = await contractFactory.deploy(weth);
    await contract.deployed();
    return contract;
}

export async function deployForwarderRegistry(): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('ForwarderRegistry');
    const contract = await contractFactory.deploy();
    await contract.deployed();
    return contract;
}

export async function deployFeeManager(feeRecipient: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapFeeManager');
    const contract = await contractFactory.deploy(feeRecipient);
    await contract.deployed();
    return contract;
}

export async function deployFeeRegistry(master: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('FeeRegistry');
    const contract = await contractFactory.deploy(master);
    await contract.deployed();
    return contract;
}

export async function deployFeeRecipient(feeRegistry: string): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapFeeRecipient');
    const contract = await contractFactory.deploy(feeRegistry);
    await contract.deployed();
    return contract;
}

export async function deployPoolMaster(vault: string): Promise<[Contract, Contract]> {
    const forwarderRegistry = await deployForwarderRegistry();

    const contractFactory = await ethers.getContractFactory('SyncSwapPoolMaster');
    const master = await contractFactory.deploy(vault, forwarderRegistry.address, ZERO_ADDRESS);

    const feeRegistry = await deployFeeRegistry(master.address);
    const feeRecipient = await deployFeeRecipient(feeRegistry.address);
    const feeManager = await deployFeeManager(feeRecipient.address);
    await master.setFeeManager(feeManager.address);

    await master.deployed();
    return [master, feeManager];
}

export async function deployClassicPoolFactory(master: Contract): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapClassicPoolFactory');
    const contract = await contractFactory.deploy(master.address);
    await contract.deployed();

    // whtielist factory
    await master.setFactoryWhitelisted(contract.address, true);
    return contract;
}

export async function deployStablePoolFactory(master: Contract): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('SyncSwapStablePoolFactory');
    const contract = await contractFactory.deploy(master.address);
    await contract.deployed();

    // whtielist factory
    await master.setFactoryWhitelisted(contract.address, true);
    return contract;
}

export async function deployERC20Permit2(totalSupply: BigNumber): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('TestERC20Permit2');
    const contract = await contractFactory.deploy(totalSupply);
    await contract.deployed();
    return contract;
}

interface PoolFixture {
    weth: Contract;
    vault: Contract;
    master: Contract;
    factory: Contract;
    token0: Contract;
    token1: Contract;
    pool: Contract;
}

export async function classicPoolFixture(
    wallet: SignerWithAddress,
    deflating0: boolean,
    deflating1: boolean,
): Promise<PoolFixture> {
    const weth = await deployWETH9();
    const vault = await deployVault(weth.address);

    const [master, feeManager] = await deployPoolMaster(vault.address);
    feeManager.setDefaultSwapFee(1, 300); // Set fee to 0.3% for testing
    const factory = await deployClassicPoolFactory(master);

    const tokenA = deflating0 ? await deployDeflatingERC20(MAX_UINT256) : await deployTestERC20(MAX_UINT256, 18);
    const tokenB = deflating1 ? await deployDeflatingERC20(MAX_UINT256) : await deployTestERC20(MAX_UINT256, 18);
    const data = defaultAbiCoder.encode(
        ["address", "address"], [tokenA.address, tokenB.address]
    );
    await master.createPool(factory.address, data);

    const poolArtifact = await hre.artifacts.readArtifact('SyncSwapClassicPool');
    const poolAddress = await factory.getPool(tokenA.address, tokenB.address);
    const pool = new Contract(poolAddress, poolArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    return { weth, vault, master, factory, token0, token1, pool };
}

export async function stablePoolFixture(
    wallet: SignerWithAddress
): Promise<PoolFixture> {
    const weth = await deployWETH9();
    const vault = await deployVault(weth.address);

    const [master, feeManager] = await deployPoolMaster(vault.address);
    feeManager.setDefaultSwapFee(2, 100); // Set fee to 0.1% for testing
    const factory = await deployStablePoolFactory(master);

    const tokenA = await deployTestERC20(MAX_UINT256, 18);
    const tokenB = await deployTestERC20(MAX_UINT256, 18);
    const data = defaultAbiCoder.encode(
        ["address", "address"], [tokenA.address, tokenB.address]
    );
    await master.createPool(factory.address, data);

    const poolArtifact = await hre.artifacts.readArtifact('SyncSwapStablePool');
    const poolAddress = await factory.getPool(tokenA.address, tokenB.address);
    const pool = new Contract(poolAddress, poolArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    return { weth, vault, master, factory, token0, token1, pool };
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

export async function deployTestERC20(totalSupply: BigNumber, decimals: number): Promise<Contract> {
    const contractFactory = await ethers.getContractFactory('TestERC20');
    const contract = await contractFactory.deploy(totalSupply, decimals);
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

export async function routerFixture(): Promise<V2Fixture> {
    const accounts = await ethers.getSigners()
    const wallet = accounts[0];

    // deploy tokens
    const tokenA = await deployTestERC20(expandTo18Decimals(10000), 18);
    const tokenB = await deployTestERC20(expandTo18Decimals(10000), 18);
    const WETH = await deployWETH9();
    const WETHPartner = await deployTestERC20(expandTo18Decimals(10000), 18);

    // deploy core
    const vault = await deployVault(WETH.address);
    const [master, feeManager] = await deployPoolMaster(vault.address);
    const classicFactory = await deployClassicPoolFactory(master);
    const stableFactory = await deployStablePoolFactory(master);

    // deploy routers
    const router = await deployRouter(classicFactory.address, WETH.address);

    // event emitter for testing
    const routerEventEmitter = await deployRouterEventEmitter(classicFactory.address, WETH.address);

    const data = defaultAbiCoder.encode(
        ["address", "address"], [tokenA.address, tokenB.address]
    );
    await classicFactory.createPool(data);
    const pairAddress = await classicFactory.getPool(tokenA.address, tokenB.address, false);
    const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPool');;
    const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider).connect(wallet);

    const [token0, token1] = Number(tokenA.address) < Number(tokenB.address) ? [tokenA, tokenB] : [tokenB, tokenA];

    await classicFactory.createPool(data);
    const WETHPairAddress = await classicFactory.getPool(WETH.address, WETHPartner.address, false);
    const WETHPair = new Contract(WETHPairAddress, pairArtifact.abi, ethers.provider).connect(wallet);

    return {
        token0,
        token1,
        WETH,
        WETHPartner,
        factory: classicFactory,
        router,
        routerEventEmitter,
        pair,
        WETHPair
    };
}