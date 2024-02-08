// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract DexFactoryMock {
    constructor() {}

    function getPair(address, address) public pure returns (address) {
        return address(777);
    }
}
