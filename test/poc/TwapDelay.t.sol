// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../Base.t.sol";
import "./TwapHelper.sol";
import "../../src/interfaces/IHexOnePriceFeed.sol";
import "../../src/interfaces/pulsex/IPulseXRouter.sol";

/**
 *  @dev forge test --match-contract TwapDelay --rpc-url "https://rpc.pulsechain.com" -vvv
 */
contract TwapDelay is TwapHelper {
    function testTwapDelay() public {
        uint256 amount = 2000000e8;

        // give HEX to the sender for both the swap and the deposit
        _dealToken(hexToken, user, amount * 2);

        // user sells HEX to DAI
        vm.startPrank(user);
        // approve the pulsex router to spend the HEX
        IERC20(hexToken).approve(pulseXRouter, amount);

        // create a swap path from the token
        address[] memory path = new address[](2);
        path[0] = hexToken;
        path[1] = daiToken;

        // call the pulsex router to make a swap for exact tokens to tokens
        IPulseXRouter02(pulseXRouter).swapExactTokensForTokens(amount, 1, path, user, block.timestamp);
        vm.stopPrank();

        IPulseXPair pulseXPair = IPulseXPair(hexDaiPair);
        //token0 is HEX
        emit log_address(pulseXPair.token0());
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pulseXPair.getReserves();
        // consult current quote
        uint256 currentQuote = IPulseXRouter02(pulseXRouter).quote(amount, reserve0, reserve1);

        // consult TWAP quote
        uint256 twapQuote = IHexOnePriceFeed(feed).consult(hexToken, amount, daiToken);

        // check if the HEX to DAI TWAP quote is considerably higher than the spot price
        assertLt(currentQuote, twapQuote);
        emit log_named_uint("currentQuote", currentQuote);
        emit log_named_uint("twapQuote", twapQuote);

        // get user HEX balance
        uint256 hexBalance = IERC20(hexToken).balanceOf(user);

        // enable vault usage
        vm.startPrank(address(bootstrap));
        IHexOneVault(vault).setSacrificeStatus();
        vm.stopPrank();

        vm.startPrank(user);

        // approve HEX1 vault to spend the HEX
        IERC20(hexToken).approve(address(vault), hexBalance);

        // deposit HEX to the vault
        IHexOneVault(vault).deposit(hexBalance, 3800);

        // check user HEX1 balance
        uint256 hex1Balance = IERC20(hex1).balanceOf(user);

        // compare expected spot quote vs borrowed HEX1
        assertGt(hex1Balance, currentQuote);
        emit log_named_uint("hex1Balance", hex1Balance);
        emit log_named_uint("currentQuote", currentQuote);
    }
}
