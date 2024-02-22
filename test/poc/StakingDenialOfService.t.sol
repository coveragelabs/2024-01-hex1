// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Base.t.sol";

import {StakingHelper} from "./utils/StakingHelper.sol";

/// @dev forge test --match-contract StakingDenialOfService --rpc-url "https://rpc.pulsechain.com" -vvv
contract StakingDenialOfService is StakingHelper {
    function setUp() public override {
        super.setUp();

        // initial purchase amounts
        uint256 hexInitialPurchase = 1000 * 1e8;
        uint256 hexitInitialPurchase = 2000 * 1e18;
        _initialPurchase(hexInitialPurchase, hexitInitialPurchase);

        // after purchases are made the bootstrap enables staking
        vm.prank(address(bootstrap));
        staking.enableStaking();
    }

    function test_stake_denialOfService_afterInactivityDays() public {
        // bound the amount of HEX1 to stake
        uint256 amount = 500 * 1e18;

        // deal HEX1 LP to the user
        deal(address(hex1), user, amount);

        // skip the number of inactivity days after staking is enabled
        skip(2 days);

        // staking contract is bricked because of a division by zero error
        vm.startPrank(user);

        IERC20(address(hex1)).approve(address(staking), amount);
        vm.expectRevert(stdError.divisionError);
        staking.stake(address(hex1), amount);

        vm.stopPrank();
    }
}
