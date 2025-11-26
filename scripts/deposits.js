const { ethers } = require("hardhat");

async function main() {
  const bankAddress = process.env.BANK_ADDRESS;
  const token = process.env.DEPOSIT_TOKEN; // 0x0 para ETH
  const amount = process.env.AMOUNT;       // Ej: "1" ETH o "100" USDC
  const slippage = process.env.SLIPPAGE;   // amountOutMin en USDC

  const [user] = await ethers.getSigners();
  const bank = await ethers.getContractAt("KipuBankV3", bankAddress);

  console.log("\n--- Deposit ---");
  console.log("User:", user.address);

  if (token === "0x0000000000000000000000000000000000000000") {
    console.log("Depositing ETH...");

    const tx = await bank.deposit(
      token, 
      0, 
      slippage, 
      { value: ethers.parseEther(amount) }
    );

    await tx.wait();
    console.log("ETH deposit completed.");
  } else {
    console.log("Depositing ERC20 token:", token);

    const erc20 = await ethers.getContractAt("IERC20", token);

    await erc20.approve(bankAddress, amount);

    const tx = await bank.deposit(
      token,
      amount,
      slippage
    );

    await tx.wait();
    console.log("Token deposit completed.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
