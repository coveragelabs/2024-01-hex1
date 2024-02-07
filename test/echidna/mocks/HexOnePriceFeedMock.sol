// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract HexOnePriceFeedMock {
    mapping(address => mapping(address => uint256)) rates; // base rate 10000

    constructor() {}

    function setRate(address tokenIn, address tokenOut, uint256 r) public {
        rates[tokenIn][tokenOut] = r;
    }

    function update(address, address) external {}

    function consult(address tokenIn, uint256 amountIn, address tokenOut) external view returns (uint256 amountOut) {
        return amountIn * rates[tokenIn][tokenOut] / 10000;
    }
}
