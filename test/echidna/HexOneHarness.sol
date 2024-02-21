// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../src/HexOneToken.sol";
import "../../lib/properties/contracts/ERC20/internal/properties/ERC20BasicProperties.sol";
import "../../lib/properties/contracts/ERC20/internal/properties/ERC20BurnableProperties.sol";

contract CryticERC20InternalHarness is HexOneToken, CryticERC20BasicProperties, CryticERC20BurnableProperties {
    constructor() HexOneToken("HexOneToken", "HEX1") {
        // Setup balances for USER1, USER2 and USER3:
        _mint(USER1, INITIAL_BALANCE);
        _mint(USER2, INITIAL_BALANCE);
        _mint(USER3, INITIAL_BALANCE);
        // Setup total supply:
        initialSupply = totalSupply();
        isMintableOrBurnable = true;
    }
}
