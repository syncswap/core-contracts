import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Contract, ethers, Overrides } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet } from "zksync-web3";
import * as secrets from "../secrets.json";

let wallet: Wallet;
let deployer: Deployer;

const deployedContracts: Map<string, Contract> = new Map();

function _createWalletAndDeployer(
    hre: HardhatRuntimeEnvironment
): [Wallet, Deployer] {
    const wallet = new Wallet(secrets.privateKey);
    console.log(`Wallet created ${wallet.address}`);
    return [wallet, new Deployer(hre, wallet)];
}

export function initializeWalletAndDeployer(
    hre: HardhatRuntimeEnvironment
): void {
    if (wallet === undefined || deployer === undefined) {
        console.log(`Creating wallet and deployer..`);
        [wallet, deployer] = _createWalletAndDeployer(hre);
    }
}

export enum ArgumentTypes {
    ACCOUNT,
    CONTRACT
}

export function createArgument(
    type: ArgumentTypes,
    contractName?: string | undefined
): string {
    if (type === ArgumentTypes.ACCOUNT) {
        return wallet.address;
    }

    if (type === ArgumentTypes.CONTRACT) {
        if (contractName === undefined) {
            throw Error(`Must specify a contract name for CONTRACT argument type.`);
        }
        const contract: Contract | undefined = deployedContracts.get(contractName);
        if (contract === undefined) {
            throw Error(`Contract ${contractName} not found on lookup argument.`);
        }
        return contract.address;
    }

    throw Error(`Unknown argument type: ${type}`);
}

export async function deployContract(
    contractName: string,
    artifactName: string,
    constructorArguments: any[],
    overrides?: Overrides | undefined,
    additionalFactoryDeps?: ethers.utils.BytesLike[] | undefined
): Promise<ethers.Contract> {
    console.log(`\nDeploying contract '${contractName}' with arguments ${constructorArguments}`);

    const artifact = await deployer.loadArtifact(artifactName);
    const contract = await deployer.deploy(
        artifact,
        constructorArguments, {
            ...overrides,
            //feeToken: FEE_TOKEN,
        },
        additionalFactoryDeps
    );

    deployedContracts.set(contractName, contract);
    await contract.deployed();
    console.log(`Contract '${contractName}' deployed to ${contract.address}`);
    
    return contract;
}