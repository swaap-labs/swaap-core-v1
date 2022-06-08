require("dotenv").config();

const HDWalletProvider = require("@truffle/hdwallet-provider");


module.exports = {
  plugins: ["truffle-contract-size"],
  networks: {
    dev: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
    },
    polygon: {
      provider: () => new HDWalletProvider(
        //private keys array
        process.env.MNEMONIC,
        //url to ethereum node
        "https://matic-mainnet.chainstacklabs.com",
        //account index
        process.env.ACCOUNT_INDEX
      ),
      network_id: 137,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true,
      chainId: 137,
      networkCheckTimeoutnetworkCheckTimeout: 10000,
      timeoutBlocks: 200
    },
    mumbai: {
      provider: function() {
        return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to polygon node
          "https://matic-mumbai.chainstacklabs.com",
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
      network_id: 80001,
      gasPrice: 7000000000,
      confirmations: 2,
      timeoutBlocks: 1000,
      skipDryRun: true,
      timeoutBlocks: 50000,
      networkCheckTimeout: 1000000
    },
  },
  compilers: {
    solc: {
      version: "0.8.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 100
        },
        evmVersion: "london",
        outputSelection: {
          "*": {
            "": ["ast"],
            "*": [
              "evm.bytecode.object",
              "evm.deployedBytecode.object",
              "abi",
              "evm.bytecode.sourceMap",
              "evm.deployedBytecode.sourceMap",
              "metadata"
            ]
          }
        }
      }
    }
  }
};
