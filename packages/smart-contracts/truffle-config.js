const HDWalletProvider = require("truffle-hdwallet-provider");
const infuraApikey = "";
let mnemonic = "";

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*" // Match any network id
    },
    soliditycoverage: {
      host: 'localhost',
      network_id: '*', // eslint-disable-line camelcase
      port: 8555,
      gas: 0xfffffffffff,
      gasPrice: 0x01
    },
    kovan: {
      provider: function() {
        return new HDWalletProvider(mnemonic, `https://kovan.infura.io/v3/${infuraApikey}`);
      },
      network_id: 42,
      gas: 6500000, // default = 4712388
      gasPrice: 10000000000 // default = 100 gwei = 100000000000
    }
  },
  plugins: ["solidity-coverage", "truffle-security"],
  compilers: {
    solc: {
      version: "0.5.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }
  }
};
