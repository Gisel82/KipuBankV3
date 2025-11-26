// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IUniswapV2Router Minimal Interface
/// @notice Minimal functions required by KipuBankV3 for swapping tokens
interface IUniswapV2Router {
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}
