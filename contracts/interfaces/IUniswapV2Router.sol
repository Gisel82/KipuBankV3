/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IUniswapV2Router {
    // Retorna la dirección del WETH del router
    function WETH() external view returns (address);

    // Swap de ETH a tokens
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    // Swap de tokens a tokens
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}
