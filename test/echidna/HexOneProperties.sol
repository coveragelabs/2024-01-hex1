// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../lib/properties/contracts/util/Hevm.sol";
import "../../lib/properties/contracts/util/PropertiesHelper.sol";

import "../../src/HexOneStaking.sol";
import "../../src/HexitToken.sol";
import "../../src/HexOneBootstrap.sol";
import "../../src/HexOneVault.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/HexOnePriceFeedMock.sol";
import "./mocks/DexRouterMock.sol";
import "./mocks/DexFactoryMock.sol";
import "./mocks/HexMockToken.sol";
import "./wraps/HexitTokenWrap.sol";
import "./wraps/Hex1TokenWrap.sol";
import "./wraps/HexOneStakingWrap.sol";

contract User {
    function proxy(address target, bytes memory data) public returns (bool success, bytes memory err) {
        return target.call(data);
    }

    function approveERC20(ERC20 target, address spender) public {
        target.approve(spender, type(uint256).max);
    }
}

contract HexOneProperties is PropertiesAsserts {
    //init mints
    uint256 private initialMintHex;
    uint256 private initialMintToken;

    //user data
    uint256 private totalNbUsers;
    User[] private users;
    mapping(User user => uint256[] stakeIds) userToStakeids;

    //token data
    address[] private stakeTokens;
    address[] private sacrificeTokens;

    // contracts

    //internal
    HexOnePriceFeedMock private hexOnePriceFeedMock;
    HexitTokenWrap private hexit;
    Hex1TokenWrap private hex1;

    HexOneBootstrap private hexOneBootstrap;
    HexOneStakingWrap private hexOneStakingWrap;
    HexOneVault private hexOneVault;

    //external tokens
    HexMockToken private hexx;
    ERC20Mock private dai;
    ERC20Mock private wpls;
    ERC20Mock private plsx;
    ERC20Mock private hex1dai;

    //pulsex mocks
    DexRouterMock private routerMock;
    DexFactoryMock private factoryMock;

    constructor() {
        // config -----------
        totalNbUsers = 10;

        initialMintHex = 1000000e8;
        initialMintToken = 1000000 ether;

        uint16 hexDistRate = 10;
        uint16 hexitDistRate = 10;
        // ------------------
        User teamWallet = new User();

        //internal tokens
        hex1 = new Hex1TokenWrap("Hex One Token", "HEX1");
        hexit = new HexitTokenWrap("Hexit Token", "HEXIT");
        hex1dai = new ERC20Mock("HEX1/DAI LP Token", "HEX1DAI");

        //external tokens
        hexx = new HexMockToken(); //8 decimals
        dai = new ERC20Mock("DAI token", "DAI");
        wpls = new ERC20Mock("WPLS token", "WPLS");
        plsx = new ERC20Mock("PLSX token", "PLSX");

        //pulsex init
        routerMock = new DexRouterMock(address(hex1dai));
        factoryMock = new DexFactoryMock(address(hex1dai));

        //init func contracts
        hexOneVault = new HexOneVault(address(hexx), address(dai), address(hex1));
        hexOneStakingWrap = new HexOneStakingWrap(address(hexx), address(hexit), hexDistRate, hexitDistRate);
        hexOnePriceFeedMock = new HexOnePriceFeedMock();
        hexOneBootstrap = new HexOneBootstrap(
            address(routerMock),
            address(factoryMock),
            address(hexx),
            address(hexit),
            address(dai),
            address(hex1),
            address(teamWallet)
        );

        stakeTokens = new address[](3); // prepare the allowed staking tokens
        stakeTokens[0] = address(hex1dai);
        stakeTokens[1] = address(hex1);
        stakeTokens[2] = address(hexit);

        uint16[] memory weights = new uint16[](3); // prepare the distribution weights for each stake token
        weights[0] = 700;
        weights[1] = 200;
        weights[2] = 100;

        sacrificeTokens = new address[](4); // prepare sacrifice tokens
        sacrificeTokens[0] = address(hexx);
        sacrificeTokens[1] = address(dai);
        sacrificeTokens[2] = address(wpls);
        sacrificeTokens[3] = address(plsx);

        uint16[] memory multipliers = new uint16[](4); // create an array with the corresponding multiplier for each sacrifice token
        multipliers[0] = 5555;
        multipliers[1] = 3000;
        multipliers[2] = 2000;
        multipliers[3] = 1000;

        //set circular dependencies
        hex1.setHexOneVault(address(hexOneVault));

        hexit.setHexOneBootstrap(address(hexOneBootstrap));

        hexOneStakingWrap.setBaseData(address(hexOneVault), address(hexOneBootstrap));
        hexOneStakingWrap.setStakeTokens(stakeTokens, weights);

        hexOneVault.setBaseData(address(hexOnePriceFeedMock), address(hexOneStakingWrap), address(hexOneBootstrap));

        hexOneBootstrap.setBaseData(address(hexOnePriceFeedMock), address(hexOneStakingWrap), address(hexOneVault));
        hexOneBootstrap.setSacrificeTokens(sacrificeTokens, multipliers);

        /// set initial prices
        setPrices(address(hexx), address(dai), 15275940385037058);
        setPrices(address(hexx), address(hex1), 15275940385037058);
        setPrices(address(plsx), address(dai), 48267909955849);
        setPrices(address(wpls), address(dai), 120458801936871);
        setPrices(address(hex1), address(dai), 1e18);

        /// fund router swapper
        hexx.mint(address(routerMock), 1000000e8);
        dai.mint(address(routerMock), 1000000 ether);
        wpls.mint(address(routerMock), 1000000 ether);
        plsx.mint(address(routerMock), 1000000 ether);

        /// setup users (admin is this contract)
        // user
        for (uint256 i = 0; i < totalNbUsers; i++) {
            User user = new User();
            users.push(user);

            // all users get an initial supply of 1MM dai and hex - change to cheatcode
            hexx.mint(address(user), initialMintHex);
            dai.mint(address(user), initialMintToken);
            wpls.mint(address(user), initialMintToken);
            plsx.mint(address(user), initialMintToken);

            // approve all contracts
            user.approveERC20(hexx, address(hexOneVault));
            user.approveERC20(hex1, address(hexOneVault));

            user.approveERC20(hexit, address(hexOneStakingWrap));
            user.approveERC20(hex1, address(hexOneStakingWrap));
            user.approveERC20(hex1dai, address(hexOneStakingWrap));

            user.approveERC20(hexx, address(hexOneBootstrap));
            user.approveERC20(dai, address(hexOneBootstrap));
            user.approveERC20(wpls, address(hexOneBootstrap));
            user.approveERC20(plsx, address(hexOneBootstrap));
        }
    }

    // --------------------- State updates --------------------- (Here we will be defining all state update functions)

    event LogUint(uint256);
    /// ----- HexOneVault -----

    function randDeposit(uint256 randUser, uint256 randAmount, uint256 randDuration) public {
        User user = users[randUser % users.length];

        uint256 amount = clampBetween(randAmount, 1, initialMintHex / 4);
        uint16 duration = uint16(clampBetween(randDuration, hexOneVault.MIN_DURATION(), hexOneVault.MAX_DURATION()));

        (bool success, bytes memory data) =
            user.proxy(address(hexOneVault), abi.encodeWithSignature("deposit(uint256,uint16)", amount, duration));
        require(success);

        (, uint256 stakeId) = abi.decode(data, (uint256, uint256));

        userToStakeids[user].push(stakeId);
    }

    function randClaimVault(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        (bool success,) = user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.claim.selector, stakeId));
        require(success);
    }

    function randLiquidate(uint256 randUser, uint256 randDepositor, uint256 randStakeId) public {
        User userLiquidator = users[randUser % users.length];
        User userDepositor = users[randDepositor % users.length];

        uint256 stakeId = userToStakeids[userDepositor][randStakeId % userToStakeids[userDepositor].length];

        (bool success,) = userLiquidator.proxy(
            address(hexOneVault),
            abi.encodeWithSelector(hexOneVault.liquidate.selector, address(userDepositor), stakeId)
        );
        require(success);
    }

    function randBorrow(uint256 randUser, uint256 randAmount, uint256 randStakeId) public {
        User user = users[randUser % users.length];

        (uint256 totalAmount,, uint256 totalBorrowed) = hexOneVault.userInfos(address(user));
        uint256 totalPossibleBorrowAmount = hexOnePriceFeedMock.consult(address(hexx), totalAmount, address(hex1));

        uint256 possibleBorrowAmount = totalPossibleBorrowAmount - totalBorrowed;

        require(possibleBorrowAmount != 0);

        uint256 amount = clampBetween(randAmount, 1, possibleBorrowAmount);
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        (bool success,) =
            user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.borrow.selector, amount, stakeId));
        require(success);
    }

    /// ----- HexOneStaking -----

    function randStake(uint256 randUser, uint256 randAmount, uint256 randStakeToken) public {
        User user = users[randUser % users.length];

        address token = stakeTokens[randStakeToken % stakeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, initialMintToken / 4);

        (bool success,) = user.proxy(
            address(hexOneStakingWrap), abi.encodeWithSelector(hexOneStakingWrap.stake.selector, token, amount)
        );
        require(success);
    }

    function randUnstake(uint256 randUser, uint256 randAmount, uint256 randStakeToken) public {
        User user = users[randUser % users.length];

        address token = stakeTokens[randStakeToken % stakeTokens.length];
        uint256 amount = randAmount % hexOneStakingWrap.getPoolInfoStakeAmount(address(user), token);

        (bool success,) = user.proxy(
            address(hexOneStakingWrap), abi.encodeWithSelector(hexOneStakingWrap.unstake.selector, token, amount)
        );
        require(success);
    }

    function randClaimStaking(uint256 randUser, uint256 randStakeToken) public {
        User user = users[randUser % users.length];
        address token = stakeTokens[randStakeToken % stakeTokens.length];

        (bool success,) =
            user.proxy(address(hexOneStakingWrap), abi.encodeWithSelector(hexOneStakingWrap.claim.selector, token));
        require(success);
    }
    /// ----- HexOneBootstrap -----

    function randSacrifice(uint256 randUser, uint256 randToken, uint256 randAmountIn) public {
        User user = users[randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];

        uint256 amount = clampBetween(randAmountIn, 1, (token == address(hexx) ? initialMintHex : initialMintToken) / 4);

        (bool success,) = user.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(success);
    }

    function randClaimSacrifice(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));
        require(success);
    }

    function randClaimAirdrop(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimAirdrop.selector));
        require(success);
    }

    // admin calls
    function auxSetSacrificeStart() public {
        hexOneBootstrap.setSacrificeStart(block.timestamp);
    }

    function auxStartAirdrop() public {
        hexOneBootstrap.startAidrop();
    }

    function auxProcessSacrifice() public {
        uint256 totalHexAmount = hexOneBootstrap.totalHexAmount();
        uint256 minAmountOut = (totalHexAmount * 1250) / 10000;

        hexOneBootstrap.processSacrifice(minAmountOut);
    }

    // user calls
    function randAddLiquidity(uint256 randUser, uint256 randAmount) public {
        User user = users[randUser % users.length];

        uint256 hex1Amount = clampBetween(randAmount, 1, hex1.balanceOf(address(user)) / 4);
        require(hex1Amount != 0);
        uint256 daiAmount = hexOnePriceFeedMock.consult(address(hex1), hex1Amount, address(dai));

        (bool success,) = user.proxy(
            address(routerMock),
            abi.encodeWithSelector(
                routerMock.addLiquidity.selector,
                address(hex1),
                address(dai),
                hex1Amount,
                daiAmount,
                0,
                0,
                address(0),
                0
            )
        );
        require(success);
    }

    /// ----- General state updates -----
    function randSetPrices(uint256 randTokenIn, uint256 randRate) public {
        address tokenIn = sacrificeTokens[randTokenIn % sacrificeTokens.length];
        address tokenOut = address(dai);

        require(tokenIn != tokenOut);

        int256 r = int256(hexOnePriceFeedMock.getRate(tokenIn, tokenOut)) + int256(clampBetween(randRate, 0, 1e10));

        require(r != 0);

        setPrices(tokenIn, tokenOut, uint256(r));
    }

    function randIncreaseTimestamp(uint8 randTs) public {
        hevm.warp(block.timestamp + randTs * 1 days); // add between 1 day and 255 days to timestamps
    }

    // ---------------------- Invariants ---------------------- (Here we will be defining all our invariants)

    /// @custom:invariant - HEXIT token emmission should never be more than the max emission.
    // function hexitEmissionIntegrity() public {}

    // ---------------------- HexOneStaking ----------------------

    /// @custom:invariant - HexOneStaking daily Hexit rewards cannot differ from 1%.
    // @audit-ok property checked (but not consistent with initial code base)
    function hexOneStakingDailyHexitRewardsCannotDifferFrom1Percent() public {
        // min threshold = 98 bps = 0,98%
        uint256 rewardShareMinThreshold = 98;
        // max threshold = 102 bps = 1,02%
        uint256 rewardShareMaxThreshold = 102;

        (,,, uint256 currentStakingDay,) = hexOneStakingWrap.pools(address(hexit));

        if (currentStakingDay > 0) {
            // @note pool history does not have available assets (fixed by the client). we need to do this in a different way
            (uint256 availableAssets,, uint256 amountToDistribute) =
                hexOneStakingWrap.poolHistory(currentStakingDay - 1, address(hexit));
            uint256 share = (amountToDistribute * 10_000) / availableAssets;

            // emit LogUint(share);

            if (amountToDistribute > 0) {
                assert(share >= rewardShareMinThreshold && share <= rewardShareMaxThreshold);
            } else {
                assert(share == 0);
            }
        }
    }

    /// @custom:invariant - HexOneStaking daily Hex rewards cannot differ from 1%.
    // @audit-ok property checked (but not consistent with initial code base)
    // function hexOneStakingDailyHexRewardsCannotDifferFrom1Percent() public {
    //     // min threshold = 98 bps = 0,98%
    //     uint256 rewardShareMinThreshold = 98;
    //     // max threshold = 102 bps = 1,02%
    //     uint256 rewardShareMaxThreshold = 102;

    //     (uint256 totalAssets, uint256 distributedAssets,, uint256 currentStakingDay,) =
    //         hexOneStakingWrap.pools(address(hexx));

    //     if (currentStakingDay > 0) {
    //         // @note pool history does not have available assets (fixed by the client). we need to this in a different way
    //         (uint256 availableAssets,, uint256 amountToDistribute) =
    //             hexOneStakingWrap.poolHistory(currentStakingDay - 1, address(hexx));
    //         uint256 share = (amountToDistribute * 10_000) / availableAssets;

    //         // emit LogUint(share);

    //         if (amountToDistribute > 0) {
    //             assert(share >= rewardShareMinThreshold && share <= rewardShareMaxThreshold);
    //         } else {
    //             assert(share == 0);
    //         }
    //     }
    // }

    /// @custom:invariant - HexOneStaking Hex shares to give is always proportional to increase in balance.
    // @audit-issue property broken
    // function hexOneStakingHexSharesToGiveIsAlwaysProportionalToIncreaseInBalance(
    //     uint256 randAmount,
    //     uint256 randStakeToken
    // ) public {
    //     uint256 offset = 100;

    //     address stakeToken = stakeTokens[randStakeToken % stakeTokens.length];

    //     address xToken = stakeTokens[(randStakeToken + 1) % stakeTokens.length];
    //     uint256 xTokenBalance = hexOneStakingWrap.totalStakedAmount(xToken);
    //     uint256 xTokenWeight = hexOneStakingWrap.stakeTokenWeights(xToken);

    //     address yToken = stakeTokens[(randStakeToken + 2) % stakeTokens.length];
    //     uint256 yTokenBalance = hexOneStakingWrap.totalStakedAmount(yToken);
    //     uint256 yTokenWeight = hexOneStakingWrap.stakeTokenWeights(yToken);

    //     uint256 stakeAmount = (randAmount % initialMint) / 1000 + 1;
    //     uint256 shares = calculateShares(stakeToken, stakeAmount);

    //     if (shares > 0) {
    //         uint256 stakeTokenBalance = hexOneStakingWrap.totalStakedAmount(stakeToken);
    //         uint256 stakeTokenBalanceIncreaseFactor = ((stakeAmount + stakeTokenBalance) * 10_000) / stakeTokenBalance;

    //         (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(hexx));

    //         uint256 stakeTokenTotalShares =
    //             totalShares - (xTokenBalance * xTokenWeight) - (yTokenBalance * yTokenWeight);
    //         uint256 hexSharesIncreaseFactor = ((shares + stakeTokenTotalShares) * 10_000) / stakeTokenTotalShares;

    //         emit LogUint(stakeTokenBalanceIncreaseFactor);
    //         emit LogUint(hexSharesIncreaseFactor);

    //         assert(
    //             stakeTokenBalanceIncreaseFactor >= hexSharesIncreaseFactor - offset
    //                 && stakeTokenBalanceIncreaseFactor <= hexSharesIncreaseFactor + offset
    //         );
    //     }
    // }

    /// @custom:invariant - HexOneStaking Hexit shares to give is always proportional to increase in balance.
    // @audit-issue property broken
    // function hexOneStakingHexitSharesToGiveIsAlwaysProportionalToIncreaseInBalance(
    //     uint256 randAmount,
    //     uint256 randStakeToken
    // ) public {
    //     uint256 offset = 100;

    //     address stakeToken = stakeTokens[randStakeToken % stakeTokens.length];

    //     address xToken = stakeTokens[(randStakeToken + 1) % stakeTokens.length];
    //     uint256 xTokenBalance = hexOneStakingWrap.totalStakedAmount(xToken);
    //     uint256 xTokenWeight = hexOneStakingWrap.stakeTokenWeights(xToken);

    //     address yToken = stakeTokens[(randStakeToken + 2) % stakeTokens.length];
    //     uint256 yTokenBalance = hexOneStakingWrap.totalStakedAmount(yToken);
    //     uint256 yTokenWeight = hexOneStakingWrap.stakeTokenWeights(yToken);

    //     uint256 stakeAmount = (randAmount % initialMint) / 1000 + 1;
    //     uint256 shares = calculateShares(stakeToken, stakeAmount);

    //     if (shares > 0) {
    //         uint256 stakeTokenBalance = hexOneStakingWrap.totalStakedAmount(stakeToken);
    //         uint256 stakeTokenBalanceIncreaseFactor = ((stakeAmount + stakeTokenBalance) * 10_000) / stakeTokenBalance;

    //         (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(hexit));

    //         uint256 stakeTokenTotalShares =
    //             totalShares - (xTokenBalance * xTokenWeight) - (yTokenBalance * yTokenWeight);
    //         uint256 hexSharesIncreaseFactor = ((shares + stakeTokenTotalShares) * 10_000) / stakeTokenTotalShares;

    //         emit LogUint(stakeTokenBalanceIncreaseFactor);
    //         emit LogUint(hexSharesIncreaseFactor);

    //         assert(
    //             stakeTokenBalanceIncreaseFactor >= hexSharesIncreaseFactor - offset
    //                 && stakeTokenBalanceIncreaseFactor <= hexSharesIncreaseFactor + offset
    //         );
    //     }
    // }

    /// @custom:invariant - Users cannot withdraw more Hex1 than they deposit
    // @audit-ok property checked
    // function usersCannotWithdrawMoreHex1ThanTheyDeposit(uint256 randAmount) public {
    //     for (uint8 i; i < users.length; ++i) {
    //         User user = users[i];
    //         uint256 userStakedAmount = hexOneStakingWrap.getPoolInfoStakeAmount(address(user), address(hex1));
    //         if (userStakedAmount > 0) {
    //             uint256 amount = randAmount % hexOneStakingWrap.getPoolInfoStakeAmount(address(user), address(hex1));
    //             (uint256 stakedAmountBefore,,,,,,,,,) = hexOneStakingWrap.stakingInfos(address(user), address(hex1));

    //             uint256 beforeBalance = hex1.balanceOf(address(user)) + stakedAmountBefore;

    //             emit LogUint(hex1.balanceOf(address(user)));
    //             emit LogUint(stakedAmountBefore);
    //             emit LogUint(beforeBalance);

    //             (bool success,) = user.proxy(
    //                 address(hexOneStakingWrap),
    //                 abi.encodeWithSelector(hexOneStakingWrap.unstake.selector, address(hex1), amount)
    //             );
    //             require(success);

    //             (uint256 stakedAmountAfter,,,,,,,,,) = hexOneStakingWrap.stakingInfos(address(user), address(hex1));
    //             uint256 afterBalance = hex1.balanceOf(address(user)) + stakedAmountAfter;

    //             emit LogUint(hex1.balanceOf(address(user)));
    //             emit LogUint(stakedAmountAfter);
    //             emit LogUint(beforeBalance);

    //             assert(beforeBalance == afterBalance);
    //         }
    //     }
    // }

    /// @custom:invariant - Hexit unstake amount is always greater than or equals to stake amount
    // @audit-ok property checked
    // function hexitUnstakeAmountIsAlwaysGreaterThanOrEqualsToStakeAmount(uint256 randAmount) public {
    //     for (uint8 i; i < users.length; ++i) {
    //         User user = users[i];
    //         uint256 userStakedAmount = hexOneStakingWrap.getPoolInfoStakeAmount(address(user), address(hexit));
    //         if (userStakedAmount > 0) {
    //             uint256 amount = randAmount % hexOneStakingWrap.getPoolInfoStakeAmount(address(user), address(hexit));
    //             emit LogUint(amount);

    //             (uint256 stakedAmountBefore,,,,,,, uint256 unclaimedHexit,,) =
    //                 hexOneStakingWrap.stakingInfos(address(user), address(hexit));
    //             uint256 beforeBalance = hexit.balanceOf(address(user)) + stakedAmountBefore;

    //             emit LogUint(unclaimedHexit);
    //             emit LogUint(hexit.balanceOf(address(user)));
    //             emit LogUint(stakedAmountBefore);
    //             emit LogUint(beforeBalance);

    //             (bool success,) = user.proxy(
    //                 address(hexOneStakingWrap),
    //                 abi.encodeWithSelector(hexOneStakingWrap.unstake.selector, address(hexit), amount)
    //             );
    //             require(success);

    //             (uint256 stakedAmountAfter,,,,,,,,,) = hexOneStakingWrap.stakingInfos(address(user), address(hexit));
    //             uint256 afterBalance = hexit.balanceOf(address(user)) + stakedAmountAfter;

    //             emit LogUint(hexit.balanceOf(address(user)));
    //             emit LogUint(stakedAmountAfter);
    //             emit LogUint(afterBalance);

    //             assert(afterBalance >= beforeBalance);
    //         }
    //     }
    // }

    /// @custom:invariant - HEX1 minted must always be equal to the total amount of HEX1 needed to claim or liquidate all deposits
    // function hexitLiquidationsIntegrity() public {
    //     uint256 totalHexoneUsersAmount;
    //     uint256 totalHexoneProtocolAmount;

    //     for (uint256 i = 0; i < totalNbUsers; i++) {
    //         (,, uint256 totalBorrowed) = hexOneVault.userInfos(address(users[i]));
    //         totalHexoneProtocolAmount += totalBorrowed;
    //     }

    //     for (uint256 i = 0; i < totalNbUsers; i++) {
    //         totalHexoneUsersAmount += hex1.balanceOf(address(users[i]));
    //     }

    //     assert(totalHexoneUsersAmount == totalHexoneProtocolAmount);
    // }

    /// @custom:invariant - history.amountToDistribute for a given day must always be == 0 whenever pool.totalShares is also == 0
    // function poolAmountStateIntegrity() public {
    //     for (uint256 i = 0; i < stakeTokens.length; i++) {
    //         (,,, uint256 currentStakingDay,) = hexOneStakingWrap.pools(address(stakeTokens[i]));
    //         (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(stakeTokens[i]));
    //         (, uint256 amountToDistribute) = hexOneStakingWrap.poolHistory(currentStakingDay, address(stakeTokens[i]));

    //         if (totalShares == 0 || amountToDistribute == 0) {
    //             assert(totalShares == amountToDistribute);
    //         }
    //     }
    // }

    // ---------------------- Helpers ------------------------- (Free area to define helper functions)
    function setPrices(address tokenIn, address tokenOut, uint256 r) internal {
        routerMock.setRate(tokenIn, tokenOut, r);
        hexOnePriceFeedMock.setRate(tokenIn, tokenOut, r);
    }

    function calculateShares(address _stakeToken, uint256 _amount) internal returns (uint256) {
        uint256 shares = (_amount * hexOneStakingWrap.stakeTokenWeights(_stakeToken)) / 1000;
        return convertToShares(_stakeToken, shares);
    }

    function convertToShares(address _token, uint256 _amount) internal returns (uint256) {
        uint8 decimals = TokenUtils.expectDecimals(_token);
        if (decimals >= 18) {
            return _amount / (10 ** (decimals - 18));
        } else {
            return _amount * (10 ** (18 - decimals));
        }
    }
}
