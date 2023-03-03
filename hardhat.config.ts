import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-verify";
import "@matterlabs/hardhat-zksync-solc";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-solhint";

module.exports = {
  // hardhat-zksync-solc
  // The compiler configuration for zkSync artifacts.
  zksolc: {
    version: "latest",
    compilerSource: "binary",
    settings: {
      compilerPath: "./zksolc-linux-amd64-musl-v1.3.5",
    },
  },

  // hardhat-zksync-deploy
  // Run `deploy-zksync` task to deploy zkSync artifacts into following network.
  // Note that it will use `artifacts` instead of `artifacts-zk`.
  zkSyncDeploy: {
    zkSyncNetwork: "https://zksync2-testnet.zksync.dev",
    ethNetwork: "goerli",
  },

  // The compiler configuration for normal artifacts.
  solidity: {
    version: "0.8.15",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yul: false
        }
      },
    }
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },

  // tests
  defaultNetwork: 'hardhat',
  networks: {
    // Run compile task with this network to generate normal artifacts.
    // Example: `yarn hardhat compile --network hardhat`
    hardhat: {
      chainId: 280,
      gasMultiplier: 0,
      initialBaseFeePerGas: 0,
    },

    goerli: {
      url: "https://endpoints.omniatech.io/v1/eth/goerli/public"
    },

    // Run compile task with this network to generate `artifacts-zk` and `cache-zk`.
    // Example: `yarn hardhat compile --network zksync`
    zkTestnet: {
      zksync: true,
      ethNetwork: "goerli",
      url: 'https://zksync2-testnet.zksync.dev',
      chainId: 280
    },
  },
  mocha: {
    timeout: 40000
  },
};