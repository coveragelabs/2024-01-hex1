// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "../mocks/ERC20Mock.sol";

// this contract need to be funded in tokens to work
contract DexRouterMock {
    mapping(address => mapping(address => uint256)) rates; // base rate 10000

    address hex1dai;

    constructor(address _hex1dai) {
        hex1dai = _hex1dai;
    }

    function setRate(address tokenIn, address tokenOut, uint256 r) public {
        rates[tokenIn][tokenOut] = r;
    }

    // we assume path.lenght == 2
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        ERC20Mock(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = amountIn * rates[path[0]][path[1]] / 10000;
        require(amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        ERC20Mock(path[1]).transfer(to, amountOut);
        amounts[1] = amountOut;
    }

    function addLiquidity(
        address hex1,
        address dai,
        uint256 hex1Amount,
        uint256 daiAmount,
        uint256,
        uint256,
        address,
        uint256
    ) external returns (uint256, uint256, uint256) {
        ERC20Mock(hex1).transferFrom(msg.sender, address(this), hex1Amount);
        ERC20Mock(dai).transferFrom(msg.sender, address(this), daiAmount);
        ERC20Mock(hex1dai).mint(msg.sender, hex1Amount);
        return (hex1Amount, daiAmount, hex1Amount);
    }
}

// setRate() => change the exchange rate of swapExactTokensForTokens
// swapExactTokensForTokens(_amountIn, _amountOutMin, path, address(this), deadline) => no slippage
// addLiquidity(hexOneToken,daiToken,hexOneMinted,amountOut[1],hexOneMinted, amountOut[1], address(this), deadline); => do nothng
