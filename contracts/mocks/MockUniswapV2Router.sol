// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapV2Router {
    address public immutable WETH;

    constructor(address _weth) {
        WETH = _weth;
    }

    // ETH → USDC
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        deadline; // unused

        // mock: 1 ETH = 2000 USDC
        uint out = msg.value * 2000;

        require(out >= amountOutMin, "MockRouter: slippage");

        IERC20 usdc = IERC20(path[path.length - 1]);
        usdc.transfer(to, out);

        amounts[0] = msg.value;
        amounts[1] = out;
    }

    // ERC20 → USDC
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        deadline;

        // mock: 1 token = 2 USDC
        uint out = amountIn * 2;

        require(out >= amountOutMin, "MockRouter: slippage");

        IERC20 usdc = IERC20(path[path.length - 1]);
        usdc.transfer(to, out);

        amounts[0] = amountIn;
        amounts[1] = out;
    }
}
