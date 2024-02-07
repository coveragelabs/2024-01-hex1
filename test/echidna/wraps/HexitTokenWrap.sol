// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../../src/HexitToken.sol";

contract HexitTokenWrap is HexitToken {
    constructor(string memory _name, string memory _symbol) HexitToken(_name, _symbol) {}

    function mintAdmin(address _recipient, uint256 _amount) external {
        _mint(_recipient, _amount);
    }
}
