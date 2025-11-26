const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contract with account:", deployer.address);
  console.log("Balance:", (await deployer.getBalance()).toString());

  const maxWithdrawal = ethers.parseUnits("2000", 6); // 2000 USDC
  const bankCapUSD = ethers.parseUnits("2000000", 6); // 2,000,000 USDC

  const usdcAddress = process.env.USDC_ADDRESS;
  const routerAddress = process.env.ROUTER_ADDRESS;

  const KipuBankV3 = await ethers.getContractFactory("KipuBankV3");

  const bank = await KipuBankV3.deploy(
    maxWithdrawal,
    bankCapUSD,
    usdcAddress,
    routerAddress
  );

  console.log("KipuBankV3 deployed at:", await bank.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
