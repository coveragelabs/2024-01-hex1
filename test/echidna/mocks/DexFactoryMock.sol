// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract DexFactoryMock {
    address hex1dai;

    constructor(address _hex1dai) {
        hex1dai = _hex1dai;
    }

    function getPair(address, address) public view returns (address) {
        return hex1dai;
    }
}
