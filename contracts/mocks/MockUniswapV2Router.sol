// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../mocks/ERC20Mock.sol";
import "../interfaces/IUniswapV2Router.sol";

contract MockUniswapV2Router is IUniswapV2Router {
    address private immutable _weth;

    constructor(address weth_) {
        _weth = weth_;
    }

    // Implementación correcta del override de WETH
    function WETH() external view override returns (address) {
        return _weth;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external payable override returns (uint[] memory amounts) {
        require(path[path.length - 1] != address(0), "invalid path");

        // mock: 1 ETH = 2000 USDC (accounting for decimals: ETH=18, USDC=6)
        uint256 ethAmount = msg.value;
        uint256 out = (ethAmount * 2000) / 1e18;

        //Validate slippage (minimum output amount)
        require(out >= amountOutMin, "Insufficient output amount");

        //Mint tokens to the recipient (for testing purposes only)
        ERC20Mock(path[path.length - 1]).mint(to, out);

        amounts = new uint256[](2);
        amounts[0] = ethAmount;
        amounts[1] = out;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint /* deadline */
    ) external override returns (uint[] memory amounts) {
        require(path[path.length - 1] != address(0), "invalid path");

        // mock: 1 token = 2 USDC (accounting for decimals: Token=18, USDC=6)
        uint out = (amountIn * 2) / 1e18;
        require(out >= amountOutMin, "Insufficient output amount"); // Check slippage

        ERC20Mock(path[path.length - 1]).mint(to, out);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = out;
    }
}

