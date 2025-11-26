require("dotenv").config();

async function main() {
  const bankAddress = process.env.BANK_ADDRESS;

  const args = [
    process.env.MAX_WITHDRAWAL,
    process.env.BANK_CAP,
    process.env.USDC_ADDRESS,
    process.env.ROUTER_ADDRESS
  ];

  await hre.run("verify:verify", {
    address: bankAddress,
    constructorArguments: args
  });

  console.log("Verification completed.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
