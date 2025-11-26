require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },

  typechain: {
    outDir: "typechain",
    target: "ethers-v6"
  },

  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true
    }
  }
};
