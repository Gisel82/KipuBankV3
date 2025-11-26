const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("KipuBankV3", () => {
  let bank, usdc, token, router;
  let owner, user;

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    // Deploy USDC mock
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20Mock.deploy("USD Coin", "USDC", 6);

    // Mint to bank + user
    await usdc.mint(owner.address, ethers.parseUnits("1000000", 6));
    await usdc.mint(user.address, ethers.parseUnits("1000000", 6));

    // Deploy router mock
    const Router = await ethers.getContractFactory("MockUniswapV2Router");
    router = await Router.deploy(owner.address);

    // Deploy bank
    const KipuBankV3 = await ethers.getContractFactory("KipuBankV3");
    bank = await KipuBankV3.deploy(
      ethers.parseUnits("1000", 6),
      ethers.parseUnits("100000", 6),
      await usdc.getAddress(),
      await router.getAddress()
    );
  });

  it("should deposit USDC directly", async () => {
    await usdc.connect(user).approve(bank.getAddress(), 1000);

    await bank.connect(user).deposit(usdc.getAddress(), 1000, 0);

    const bal = await bank.getUserBalance(user.address);

    expect(bal).to.equal(1000);
  });

  it("should withdraw USDC", async () => {
    await usdc.connect(user).approve(bank.getAddress(), 2000);
    await bank.connect(user).deposit(usdc.getAddress(), 2000, 0);

    await bank.connect(user).withdraw(1000);

    const bal = await bank.getUserBalance(user.address);

    expect(bal).to.equal(1000);
  });

  it("should not exceed max withdrawal", async () => {
    await usdc.connect(user).approve(bank.getAddress(), 2000);
    await bank.connect(user).deposit(usdc.getAddress(), 2000, 0);

    await expect(
      bank.connect(user).withdraw(ethers.parseUnits("2000", 6))
    ).to.be.revertedWithCustomError(bank, "MaxWithdrawalExceeded");
  });
});
