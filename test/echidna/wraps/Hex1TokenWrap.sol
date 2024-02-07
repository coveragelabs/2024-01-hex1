// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../../src/HexOneToken.sol";

contract Hex1TokenWrap is HexOneToken {
    constructor(string memory _name, string memory _symbol) HexOneToken(_name, _symbol) {}

    function mintAdmin(address _recipient, uint256 _amount) external {
        _mint(_recipient, _amount);
    }
}
