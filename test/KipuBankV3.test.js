const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("KipuBankV3", function () {
  let bank, owner, user, usdc, weth, router;

  beforeEach(async function () {
    [owner, user, other] = await ethers.getSigners();

    // Deploy ERC20 USDC mock
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20Mock.deploy("USDC", "USDC", 6);
    await usdc.deployed();

    // Deploy WETH mock (dummy ERC20)
    weth = await ERC20Mock.deploy("WETH", "WETH", 18);
    await weth.deployed();

    // Deploy Uniswap router mock
    const RouterMock = await ethers.getContractFactory("UniswapV2RouterMock");
    router = await RouterMock.deploy(weth.address);
    await router.deployed();

    // Deploy KipuBankV3
    const Bank = await ethers.getContractFactory("KipuBankV3");
    bank = await Bank.deploy(
      ethers.utils.parseUnits("1000", 6),   // maxWithdrawal
      ethers.utils.parseUnits("100000", 6),// bankCapUSD
      usdc.address,
      ethers.constants.AddressZero,         // ETH/USD feed dummy
      router.address
    );
    await bank.deployed();
  });

  it("Owner has BANK_MANAGER_ROLE", async function () {
    expect(await bank.hasRole(await bank.BANK_MANAGER_ROLE(), owner.address)).to.be.true;
  });

  it("Deposit USDC updates balance", async function () {
    await usdc.mint(user.address, 1000);
    await usdc.connect(user).approve(bank.address, 1000);
    await bank.connect(user).deposit(usdc.address, 1000);
    expect(await bank.getUserBalance(user.address)).to.equal(1000);
  });

  it("Deposit ETH swaps to USDC", async function () {
    const amount = ethers.utils.parseEther("1");
    await bank.connect(user).deposit(ethers.constants.AddressZero, { value: amount });
    expect(await bank.getUserBalance(user.address)).to.equal(amount);
  });

  it("Deposit ERC20 token swaps to USDC", async function () {
    const token = await ethers.getContractFactory("ERC20Mock");
    const erc20 = await token.deploy("TOKEN", "TKN", 18);
    await erc20.deployed();
    await erc20.mint(user.address, 500);
    await erc20.connect(user).approve(bank.address, 500);

    await bank.connect(owner).supportToken(erc20.address);
    await bank.connect(user).deposit(erc20.address, 500);
    expect(await bank.getUserBalance(user.address)).to.equal(500);
  });

  it("Deposit exceeding bankCap fails", async function () {
    const amount = ethers.utils.parseUnits("100001", 6);
    await usdc.mint(user.address, amount);
    await usdc.connect(user).approve(bank.address, amount);
    await expect(bank.connect(user).deposit(usdc.address, amount)).to.be.revertedWith("BankCapExceeded");
  });

  it("Withdraw works and reduces balance", async function () {
    await usdc.mint(user.address, 1000);
    await usdc.connect(user).approve(bank.address, 1000);
    await bank.connect(user).deposit(usdc.address, 1000);
    await bank.connect(user).withdraw(500);
    expect(await bank.getUserBalance(user.address)).to.equal(500);
  });

  it("Direct ETH transfer fails", async function () {
    await expect(user.sendTransaction({ to: bank.address, value: 1 })).to.be.revertedWith("DirectTransfer");
  });
});
