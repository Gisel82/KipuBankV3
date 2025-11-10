require("@nomicfoundation/hardhat-toolbox");
const path = require("path");

module.exports = {
  solidity: "0.8.30",
  paths: {
    sources: "./src",   
    tests: "./it",      
    cache: "./.cache",
    artifacts: "./artifacts"
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6"
  },
  resolve: {
    modules: [path.resolve(__dirname, ".deps/npm"), "npm"]
  },
  networks: {
    hardhat: {
      chainId: 1337
    }
  }
};

