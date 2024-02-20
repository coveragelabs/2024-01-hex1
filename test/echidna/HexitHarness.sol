// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../src/HexitToken.sol";
import "../../lib/properties/contracts/ERC20/internal/properties/ERC20BasicProperties.sol";

contract CryticERC20InternalHarness is HexitToken, CryticERC20BasicProperties {
    constructor() HexitToken("HexitToken", "HEXIT") {
        // Setup balances for USER1, USER2 and USER3:
        _mint(USER1, INITIAL_BALANCE);
        _mint(USER2, INITIAL_BALANCE);
        _mint(USER3, INITIAL_BALANCE);
        // Setup total supply:
        initialSupply = totalSupply();
        isMintableOrBurnable = true;
    }
}
