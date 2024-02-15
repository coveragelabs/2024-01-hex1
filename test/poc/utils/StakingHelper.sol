// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Base.t.sol";

contract StakingHelper is Base {
    function _initialPurchase(uint256 _hexAmount, uint256 _hexitAmount) internal {
        // vault adds HEX1 to the contract
        deal(hexToken, address(vault), _hexAmount);

        vm.startPrank(address(vault));

        IERC20(hexToken).approve(address(staking), _hexAmount);
        staking.purchase(address(hexToken), _hexAmount);

        vm.stopPrank();

        // bootstrap adds HEXIT to the contract
        deal(address(hexit), address(bootstrap), _hexitAmount);

        vm.startPrank(address(bootstrap));

        hexit.approve(address(staking), _hexitAmount);
        staking.purchase(address(hexit), _hexitAmount);

        vm.stopPrank();
    }
}
