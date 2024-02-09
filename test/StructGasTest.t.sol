// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract StructGasTest is Base {
    function test_gas_cost_of_handling_structs(uint256 amount) public {
        vm.assume(amount > 1_000 * 1e8 && amount < 10_000_000 * 1e8);

        // give HEX to the sender
        deal(hexToken, user, amount);

        // start impersionating user
        vm.startPrank(user);

        // approve bootstrap to spend HEX tokens
        IERC20(hexToken).approve(address(bootstrap), amount);

        // sacrifice HEX tokens
        bootstrap.sacrifice(hexToken, amount, 0);

        // stop impersonating user
        vm.stopPrank();

        // skip 30 days so ensure that sacrifice period already ended
        skip(30 days);

        // calculate the corresponding to 12.5% of the total HEX deposited
        uint256 amountOfHexToDai = (amount * 1250) / 10000;

        // calculate the amount out min of DAI
        address[] memory path = new address[](2);
        path[0] = hexToken;
        path[1] = daiToken;
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(pulseXFactory, amountOfHexToDai, path);

        // impersonate the deployer
        vm.startPrank(deployer);

        bootstrap.processSacrifice(amounts[1]);

        // stop impersonating the deployer
        vm.stopPrank();

        // impersonate the user
        vm.startPrank(user);

        // claim HEX1 and HEXIT from the sacrifice
        (, uint256 hexOneMinted, uint256 hexitMinted) = bootstrap.claimSacrifice();

        // stop impersonating the user
        vm.stopPrank();

        // assert sacrifice claimed is set to true
        (,, bool sacrificeClaimed,) = bootstrap.userInfos(user);
        assertEq(sacrificeClaimed, true);
    }
}
