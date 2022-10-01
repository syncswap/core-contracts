import { BigNumber, Contract } from 'ethers';
import {
    defaultAbiCoder,
    keccak256,
    solidityPack,
    toUtf8Bytes
} from 'ethers/lib/utils';
import { Constants } from './constants';

const hre = require("hardhat");

export function expandTo18Decimals(n: number): BigNumber {
    return BigNumber.from(n).mul(BigNumber.from(10).pow(18));
}

export function expandToDecimals(n: number, decimals: number): BigNumber {
    return BigNumber.from(n).mul(BigNumber.from(10).pow(decimals));
}

export function getDomainSeparator(name: string, tokenAddress: string) {
    return keccak256(
        defaultAbiCoder.encode(
            ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
            [
                keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
                keccak256(toUtf8Bytes(name)),
                keccak256(toUtf8Bytes('1')),
                Constants.CHAIN_ID,
                tokenAddress
            ]
        )
    )
}

export async function getApprovalDigest(
    token: Contract,
    approve: {
        owner: string
        spender: string
        value: BigNumber
    },
    nonce: BigNumber,
    deadline: BigNumber
): Promise<string> {
    const name = await token.name()
    const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address)
    return keccak256(
        solidityPack(
            ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
            [
                '0x19',
                '0x01',
                DOMAIN_SEPARATOR,
                keccak256(
                    defaultAbiCoder.encode(
                        ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
                        [Constants.PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce, deadline]
                    )
                )
            ]
        )
    )
}

export function encodePrice(reserve0: BigNumber, reserve1: BigNumber) {
    return [reserve1.mul(BigNumber.from(2).pow(112)).div(reserve0), reserve0.mul(BigNumber.from(2).pow(112)).div(reserve1)]
}

export async function deployERC20(
    name: string,
    symbol: string,
    decimals: number,
    supply: BigNumber
): Promise<Contract> {
    const ERC20 = await hre.ethers.getContractFactory('ERC20Test');
    const token = await ERC20.deploy(name, symbol, decimals, supply);
    await token.deployed();
    return token;
}

export async function deployContract(artifact: string, constructorArguments?: any[] | undefined): Promise<Contract> {
    const contractFactory = await hre.ethers.getContractFactory(artifact); 
    const contract = await contractFactory.deploy();
    await contract.deployed();
    return contract;
}

export async function deployFactory(
    feeToSetter: string
): Promise<Contract> {
    const Factory = await hre.ethers.getContractFactory('SyncSwapFactory');
    const factory = await Factory.deploy(feeToSetter);
    await factory.deployed();
    return factory;
}

export async function deployFeeReceiver(
    factory: string,
    swapFor: string
): Promise<Contract> {
    const FeeReceiver = await hre.ethers.getContractFactory('SyncSwapFeeReceiver');
    const feeReceiver = await FeeReceiver.deploy(factory, swapFor);
    await feeReceiver.deployed();
    return feeReceiver;
}

export async function createPair(
    factory: Contract,
    tokenA: string,
    tokenB: string
): Promise<Contract> {
    await factory.createPair(tokenA, tokenB);
    const pairAddress = await factory.getPair(tokenA, tokenB);
    const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPair');
    const accounts = await hre.ethers.getSigners();
    return new Contract(pairAddress, pairArtifact.abi, hre.ethers.provider).connect(accounts[0]);
}

export async function getPair(
    factory: Contract,
    tokenA: string,
    tokenB: string
): Promise<Contract> {
    const pairAddress = await factory.getPair(tokenA, tokenB);
    const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPair');
    const accounts = await hre.ethers.getSigners();
    return new Contract(pairAddress, pairArtifact.abi, hre.ethers.provider).connect(accounts[0]);
}

export async function mineBlock(): Promise<void> {
    await hre.network.provider.send("hardhat_mine");
}

export async function mineBlockAfter(seconds: number): Promise<void> {
    await setTimeout(await hre.network.provider.send("hardhat_mine"), seconds * 1000);
}

export async function getAccounts(): Promise<any[]> {
    return await hre.ethers.getSigners();
}

export async function getAccount(id: number): Promise<any> {
    return (await getAccounts())[id];
}