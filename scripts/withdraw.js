const { ethers } = require("hardhat");

async function main() {
  const bankAddress = process.env.BANK_ADDRESS;
  const amount = process.env.AMOUNT; // en USDC 6 decimales

  const [user] = await ethers.getSigners();

  const bank = await ethers.getContractAt("KipuBankV3", bankAddress);

  console.log("\n--- Withdraw ---");
  console.log("User:", user.address);

  const tx = await bank.withdraw(amount);
  await tx.wait();

  console.log("Withdraw completed:", amount.toString());
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
