require("dotenv").config();

const HDWalletProvider = require("@truffle/hdwallet-provider");


module.exports = {
  plugins: ["truffle-contract-size"],
  networks: {
    dev: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      gasPrice: 20000000000,
    },
    kovan: {
      provider: function() {
        return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to ethereum node
          process.env.INFURA_KOVAN_ENDPOINT_URL,
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
//      gas: 12487794,
      gasPrice: 6000000000,
      network_id: 42,
      timeoutBlocks: 1000,
      skipDryRun: true,
      timeoutBlocks: 50000,
      networkCheckTimeout: 1000000
    },
	rinkeby: {
      provider: function() {
        return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to ethereum node
          process.env.INFURA_RINKEBY_ENDPOINT_URL,
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
      gasPrice: 2000000000,
      network_id: 4,
      timeoutBlocks: 1000,
      skipDryRun: true,
      timeoutBlocks: 50000,
      networkCheckTimeout: 1000000
    },
    ropsten: {
      provider: function() {
        return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to ethereum node
          process.env.INFURA_ROPSTEN_ENDPOINT_URL,
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
      gasPrice: 40000000000,
      network_id: 3,
      timeoutBlocks: 1000,
      skipDryRun: true,
      timeoutBlocks: 50000,
      networkCheckTimeout: 1000000
    },
    mumbai: {
      provider: function() {
        return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to polygon node
          process.env.INFURA_MUMBAI_ENDPOINT_URL,
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
      network_id: 80001,
      gasPrice: 7000000000,
      confirmations: 2,
      timeoutBlocks: 1000,
      skipDryRun: true,
//      websocket: true,
      timeoutBlocks: 50000,
      networkCheckTimeout: 1000000
    },
	bscTestnet: {
      provider: function() {
        return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to bsc node
          "https://data-seed-prebsc-1-s1.binance.org:8545",
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
      network_id: 97,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
    harmonyTestnet: {
      provider: () => {
		return new HDWalletProvider(
          //private keys array
          process.env.MNEMONIC,
          //url to harmony node
          "https://api.s0.b.hmny.io",
          //account index
          process.env.ACCOUNT_INDEX
        );
      },
      network_id: 1666700000,
    },
  },
  compilers: {
    solc: {
      version: "0.8.12",
      settings: {
        // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 1
        },
        evmVersion: "istanbul",
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
