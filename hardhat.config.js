require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");
require("dotenv").config();

const getAccounts = () => {
  if (!process.env.DEPLOYER_PRIVATE_KEY) {
    return [];
  }
  const pk = process.env.DEPLOYER_PRIVATE_KEY.trim();
  const formattedPk = pk.startsWith("0x") ? pk : "0x" + pk;
  if (!/^0x[a-fA-F0-9]{64}$/.test(formattedPk)) {
    return [];
  }
  return [formattedPk];
};

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

  mocha: {
    timeout: 200000
  },

  solidityLoader: {
    remappings: [
      "@openzeppelin/=node_modules/@openzeppelin/"
    ]
  },

  typechain: {
    outDir: "typechain",
    target: "ethers-v6"
  },

  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: getAccounts()
    },
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true
    }
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || ""
  }
};
