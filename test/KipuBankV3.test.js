const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("KipuBankV3", function () {
    let owner, user, user2;
    let usdc, weth, tokenA;
    let router;
    let bank;

    const maxWithdrawal = ethers.parseUnits("1000", 6);
    const bankCap = ethers.parseUnits("1000000", 6);

    beforeEach(async function () {
        [owner, user, user2] = await ethers.getSigners();

        // Mock tokens
        const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
        usdc = await ERC20Mock.deploy("USD Coin", "USDC", ethers.parseUnits("1000000", 6));
        weth = await ERC20Mock.deploy("WETH", "WETH", ethers.parseUnits("1000000", 18));
        tokenA = await ERC20Mock.deploy("TokenA", "TKA", ethers.parseUnits("1000000", 18));

        // Router mock
        const Router = await ethers.getContractFactory("MockUniswapV2Router");
        router = await Router.deploy(await weth.getAddress());

        // Bank
        const Bank = await ethers.getContractFactory("KipuBankV3");
        bank = await Bank.deploy(
            maxWithdrawal,
            bankCap,
            await usdc.getAddress(),
            await router.getAddress()
        );

        // Grant support for tokenA
        await bank.supportToken(await tokenA.getAddress());
    });

    // -----------------------------
    // CONSTRUCTOR TEST
    // -----------------------------
    it("constructor inicializa correctamente", async function () {
        expect(await bank.maxWithdrawal()).to.equal(maxWithdrawal);
        expect(await bank.bankCapUSD()).to.equal(bankCap);
        expect(await bank.usdc()).to.equal(await usdc.getAddress());
        expect(await bank.uniswapRouter()).to.equal(await router.getAddress());
    });

    // -----------------------------
    // SUPPORT TOKEN TESTS
    // -----------------------------
    it("permite agregar un token soportado", async function () {
        expect(await bank.isTokenSupported(await tokenA.getAddress())).to.equal(true);
    });

    it("permite remover un token soportado", async function () {
        await bank.unsupportToken(await tokenA.getAddress());
        expect(await bank.isTokenSupported(await tokenA.getAddress())).to.equal(false);
    });

    // -----------------------------
    // DEPOSIT ETH
    // -----------------------------
    it("permite depositar ETH y lo convierte a USDC", async function () {
        const ethDeposit = ethers.parseEther("1"); // 1 ETH

        await bank.connect(user).deposit(
            ethers.ZeroAddress,
            0,
            1,              // amountOutMin > 0 (protección slippage)
            { value: ethDeposit }
        );

        const bal = await bank.getUserBalance(user.address);
        expect(bal).to.be.gt(0);
    });

    // -----------------------------
    // DEPOSIT USDC DIRECTO
    // -----------------------------
    it("acepta depósito directo en USDC", async function () {
        const amount = ethers.parseUnits("500", 6);

        await usdc.transfer(user.address, amount);
        await usdc.connect(user).approve(bank.getAddress(), amount);

        await bank.connect(user).deposit(
            await usdc.getAddress(),
            amount,
            1
        );

        const bal = await bank.getUserBalance(user.address);
        expect(bal).to.equal(amount);
    });

    // -----------------------------
    // DEPOSIT TOKEN NO SOPORTADO
    // -----------------------------
    it("revierte al depositar token no soportado", async function () {
        const amount = ethers.parseUnits("100", 18);

        await tokenA.transfer(user.address, amount);
        await tokenA.connect(user).approve(bank.getAddress(), amount);

        // remover soporte
        await bank.unsupportToken(await tokenA.getAddress());

        await expect(
            bank.connect(user).deposit(await tokenA.getAddress(), amount, 1)
        ).to.be.revertedWithCustomError(bank, "TokenNotSupported");
    });

    // -----------------------------
    // DEPOSIT TOKEN SOPORTADO
    // -----------------------------
    it("permite depositar token soportado y swappear a USDC", async function () {
        const amount = ethers.parseUnits("100", 18);

        await tokenA.transfer(user.address, amount);
        await tokenA.connect(user).approve(bank.getAddress(), amount);

        await bank.connect(user).deposit(
            await tokenA.getAddress(),
            amount,
            1
        );

        const bal = await bank.getUserBalance(user.address);
        expect(bal).to.be.gt(0);
    });

    // -----------------------------
    // WITHDRAW
    // -----------------------------
    it("permite retirar si hay balance suficiente", async function () {
        const amount = ethers.parseUnits("500", 6);

        // deposit USDC
        await usdc.transfer(user.address, amount);
        await usdc.connect(user).approve(bank.getAddress(), amount);
        await bank.connect(user).deposit(await usdc.getAddress(), amount, 1);

        // withdraw
        await bank.connect(user).withdraw(amount);

        expect(await bank.getUserBalance(user.address)).to.equal(0);
    });

    it("revierte si retiro supera maxWithdrawal", async function () {
        const tooMuch = maxWithdrawal + 1n;

        await expect(
            bank.connect(user).withdraw(tooMuch)
        ).to.be.revertedWithCustomError(bank, "MaxWithdrawalExceeded");
    });

    // -----------------------------
    // FALLBACK / RECEIVE
    // -----------------------------
    it("rejects direct ETH transfer (receive)", async function () {
        await expect(
            user.sendTransaction({
                to: bank.getAddress(),
                value: ethers.parseEther("1")
            })
        ).to.be.reverted;
    });
});
