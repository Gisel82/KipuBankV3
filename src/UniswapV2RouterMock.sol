// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract UniswapV2RouterMock {
    address public _weth;

    constructor(address weth_) {
        _weth = weth_;
    }

    // Simula swap de ETH a token (1:1)
    function swapExactETHForTokens(
        uint256, 
        address[] calldata path, 
        address to, 
        uint256
    ) external payable returns (uint256[] memory amounts) {
        require(path.length == 2, "Path debe tener 2 tokens");
        require(path[0] == _weth, "Path[0] debe ser WETH");

        IERC20(path[1]).transfer(to, msg.value); // Simula 1 ETH = 1 token
        uint256 ;
        amounts[0] = msg.value;
        amounts[1] = msg.value;
        return amounts;
    }

    // Simula swap de token a token (1:1)
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        require(path.length == 2, "Path debe tener 2 tokens");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, amountIn); // Simula 1:1

        uint256 ;
        amounts[0] = amountIn;
        amounts[1] = amountIn;
        return amounts;
    }
    
    
    function WETH() external view returns (address) {
     return _weth;
    }
  
}
