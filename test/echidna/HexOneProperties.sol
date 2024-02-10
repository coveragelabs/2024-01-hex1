// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../lib/properties/contracts/util/Hevm.sol";

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

contract HexOneProperties {
    uint256 public totalNbUsers;
    uint256 public initialMint;
    User[] public users;
    mapping(User user => uint256[] stakeIds) userToStakeids;
    address[] public stakeTokens = new address[](3);
    address[] public sacrificeTokens = new address[](2);
    address[] public tokens = new address[](4);

    // contracts
    HexitTokenWrap public hexit;
    HexOneBootstrap public hexOneBootstrap;
    HexOneStakingWrap public hexOneStakingWrap;
    Hex1TokenWrap public hex1;
    HexOneVault public hexOneVault;
    DexRouterMock public routerMock;
    DexFactoryMock public factoryMock;
    HexMockToken public hexx;
    HexOnePriceFeedMock public hexOnePriceFeedMock;
    ERC20Mock public dai;

    constructor() payable {
        // config -----------
        totalNbUsers = 10;
        initialMint = 1000 ether;

        uint16 hexDistRate = 10;
        uint16 hexitDistRate = 10;
        // ------------------
        User receiver = new User();

        /// setup HexOne
        hex1 = new Hex1TokenWrap("Hex One Token", "HEX1");
        hexit = new HexitTokenWrap("Hexit Token", "HEXIT");
        hexx = new HexMockToken();
        routerMock = new DexRouterMock(); // TODO
        factoryMock = new DexFactoryMock(); // TODO
        dai = new ERC20Mock("DAI token", "DAI");

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
            address(receiver)
        );

        stakeTokens = new address[](3); // prepare the allowed staking tokens
        stakeTokens[0] = address(dai);
        stakeTokens[1] = address(hex1);
        stakeTokens[2] = address(hexit);
        uint16[] memory weights = new uint16[](3); // prepare the distribution weights for each stake token
        weights[0] = 700;
        weights[1] = 200;
        weights[2] = 100;
        sacrificeTokens = new address[](2);
        sacrificeTokens[0] = address(hexx);
        sacrificeTokens[1] = address(dai);
        uint16[] memory multipliers = new uint16[](2); // create an array with the corresponding multiplier for each sacrifice token
        multipliers[0] = 5555;
        multipliers[1] = 3000;

        hex1.setHexOneVault(address(hexOneVault));
        hexit.setHexOneBootstrap(address(hexOneBootstrap));
        hexOneStakingWrap.setBaseData(address(hexOneVault), address(hexOneBootstrap));
        hexOneStakingWrap.setStakeTokens(stakeTokens, weights);
        hexOneVault.setBaseData(address(hexOnePriceFeedMock), address(hexOneStakingWrap), address(hexOneBootstrap));
        hexOneBootstrap.setBaseData(address(hexOnePriceFeedMock), address(hexOneStakingWrap), address(hexOneVault));
        hexOneBootstrap.setSacrificeTokens(sacrificeTokens, multipliers);

        tokens.push(address(hex1));
        tokens.push(address(hexit));
        tokens.push(address(hexx));
        tokens.push(address(dai));

        /// set initial prices 1 == 1
        setPrices(address(dai), address(hex1), 10_000); // 10000 == 1
        setPrices(address(dai), address(hexx), 10_000);
        setPrices(address(dai), address(hexit), 10_000);
        setPrices(address(hexx), address(hex1), 10_000);
        setPrices(address(hexx), address(hexit), 10_000);
        setPrices(address(hexit), address(hex1), 10_000);

        /// fund router swapper
        hexx.mint(address(routerMock), 1000000 ether);
        dai.mint(address(routerMock), 1000000 ether);
        hexit.mintAdmin(address(routerMock), 1000000 ether);
        hex1.mintAdmin(address(routerMock), 1000000 ether);

        /// setup users (admin is this contract)
        // user
        for (uint256 i = 0; i < totalNbUsers; i++) {
            User user = new User();
            users.push(user);

            // all users get an initial supply of 100e18 of dai and hex
            hexx.mint(address(user), initialMint);
            dai.mint(address(user), initialMint);

            // approve all contracts
            user.approveERC20(hexx, address(hexOneVault));
            user.approveERC20(dai, address(hexOneVault));
            user.approveERC20(hexit, address(hexOneVault));
            user.approveERC20(hex1, address(hexOneVault));

            user.approveERC20(hexx, address(hexOneStakingWrap));
            user.approveERC20(dai, address(hexOneStakingWrap));
            user.approveERC20(hexit, address(hexOneStakingWrap));
            user.approveERC20(hex1, address(hexOneStakingWrap));

            user.approveERC20(hexx, address(hexOneBootstrap));
            user.approveERC20(dai, address(hexOneBootstrap));
            user.approveERC20(hexit, address(hexOneBootstrap));
            user.approveERC20(hex1, address(hexOneBootstrap));
        }
    }

    // --------------------- State updates --------------------- (Here we will be defining all state update functions)

    /// ----- HexOneVault -----
    event LogUint(uint256);

    function randDeposit(uint256 randUser, uint256 randAmount, uint16 randDuration) public {
        User user = users[randUser % users.length];
        uint256 amount = (randAmount % initialMint) / 1000 + 1;
        //uint16 duration = randDuration % hexOneVault.MAX_DURATION();
        uint16 duration = randDuration % 10;
        duration = duration < hexOneVault.MIN_DURATION() ? hexOneVault.MIN_DURATION() : duration;

        (bool success, bytes memory data) =
            user.proxy(address(hexOneVault), abi.encodeWithSignature("deposit(uint256,uint16)", amount, duration));
        require(success);

        (, uint256 stakeId) = abi.decode(data, (uint256, uint256));

        userToStakeids[user].push(stakeId);
    }

    function randClaimVault(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        // emit LogUint(IHexToken(hexx).currentDay());
        // assert(false);

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
        uint256 amount = (randAmount % 1 ether); // this can be improved
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];
        (bool success,) =
            user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.borrow.selector, amount, stakeId));
        require(success);
    }

    /// ----- HexOneStaking -----

    function randStake(uint256 randUser, uint256 randAmount, uint256 randStakeToken) public {
        User user = users[randUser % users.length];
        address token = stakeTokens[randStakeToken % stakeTokens.length];
        uint256 amount = (randAmount % initialMint) / 1000 + 1;

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
        uint256 amount = (randAmountIn % initialMint) / 1000 + 1;

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
    function randSetSacrificeStart() public {
        hexOneBootstrap.setSacrificeStart(block.timestamp);
    }

    function randStartAirdrop() public {
        hexOneBootstrap.startAidrop();
    }

    function randProcessSacrifice() public {
        hexOneBootstrap.processSacrifice(0);
    }

    /// ----- General state updates -----
    function randSetPrices(uint256 randTokenIn, uint256 randTokenOut, int8 randRate) public {
        address tokenIn = tokens[randTokenIn % tokens.length];
        address tokenOut = tokens[randTokenOut % tokens.length];
        require(tokenIn != tokenOut);
        int256 r = int256(hexOnePriceFeedMock.getRate(tokenIn, tokenOut)) + (int256(randRate) / 2); // will add small jump in the price [-127, 127]
        require(r > 0);

        setPrices(tokenIn, tokenOut, uint256(r));
    }

    function randIncreaseTimestamp(uint8 randTs) public {
        hevm.warp(block.timestamp + randTs * 1 days); // add between 1 day and 255 days to timestamps
    }

    // ---------------------- Invariants ---------------------- (Here we will be defining all our invariants)

    /// @custom:invariant - HEXIT token emmission should never be more than the max emission.
    function hexitEmissionIntegrity() public {}

    /// @custom:invariant - HexOneStaking daily Hexit rewards cannot differ from 1%.
    function hexOneStakingDailyHexitRewardsCannotDifferFrom1Percent() public {
        // min threshold = 98 bps = 0,98%
        uint256 rewardShareMinThreshold = 98;
        // max threshold = 102 bps = 1,02%
        uint256 rewardShareMaxThreshold = 102;

        (uint256 totalAssets, uint256 distributedAssets,, uint256 currentStakingDay,) =
            hexOneStakingWrap.pools(address(hexit));

        if (currentStakingDay > 0) {
            // @note pool history does not have available assets (fixed by the client). we need to this in a different way
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
    function hexOneStakingDailyHexRewardsCannotDifferFrom1Percent() public {
        // min threshold = 98 bps = 0,98%
        uint256 rewardShareMinThreshold = 98;
        // max threshold = 102 bps = 1,02%
        uint256 rewardShareMaxThreshold = 102;

        (uint256 totalAssets, uint256 distributedAssets,, uint256 currentStakingDay,) =
            hexOneStakingWrap.pools(address(hexx));

        if (currentStakingDay > 0) {
            // @note pool history does not have available assets (fixed by the client). we need to this in a different way
            (uint256 availableAssets,, uint256 amountToDistribute) =
                hexOneStakingWrap.poolHistory(currentStakingDay - 1, address(hexx));
            uint256 share = (amountToDistribute * 10_000) / availableAssets;

            // emit LogUint(share);

            if (amountToDistribute > 0) {
                assert(share >= rewardShareMinThreshold && share <= rewardShareMaxThreshold);
            } else {
                assert(share == 0);
            }
        }
    }

    /// @custom:invariant - HexOneStaking Hex shares to give is always proportional to increase in balance.
    function hexOneStakingHexSharesToGiveIsAlwaysProportionalToIncreaseInBalance(
        uint256 randAmount,
        uint256 randStakeToken
    ) public {
        uint256 offset = 10;

        address stakeToken = stakeTokens[randStakeToken % stakeTokens.length];

        address xToken = stakeTokens[(randStakeToken + 1) % stakeTokens.length];
        uint256 xTokenBalance = hexOneStakingWrap.totalStakedAmount(xToken);
        uint256 xTokenWeight = hexOneStakingWrap.stakeTokenWeights(xToken);

        address yToken = stakeTokens[(randStakeToken + 2) % stakeTokens.length];
        uint256 yTokenBalance = hexOneStakingWrap.totalStakedAmount(yToken);
        uint256 yTokenWeight = hexOneStakingWrap.stakeTokenWeights(yToken);

        uint256 stakeAmount = (randAmount % initialMint) / 1000 + 1;
        uint256 shares = calculateShares(stakeToken, stakeAmount);

        if (shares > 0) {
            uint256 stakeTokenBalance = hexOneStakingWrap.totalStakedAmount(stakeToken);
            uint256 stakeTokenBalanceIncreaseFactor = ((stakeAmount + stakeTokenBalance) * 10_000) / stakeTokenBalance;

            (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(hexx));

            uint256 stakeTokenTotalShares =
                totalShares - (xTokenBalance * xTokenWeight) - (yTokenBalance * yTokenWeight);
            uint256 hexSharesIncreaseFactor = ((shares + stakeTokenTotalShares) * 10_000) / stakeTokenTotalShares;

            // emit LogUint(stakeTokenBalanceIncreaseFactor);
            // emit LogUint(hexSharesIncreaseFactor);

            assert(
                stakeTokenBalanceIncreaseFactor >= hexSharesIncreaseFactor - offset
                    && stakeTokenBalanceIncreaseFactor <= hexSharesIncreaseFactor + offset
            );
        }
    }

    /// @custom:invariant - HexOneStaking Hexit shares to give is always proportional to increase in balance.
    function hexOneStakingHexitSharesToGiveIsAlwaysProportionalToIncreaseInBalance(
        uint256 randAmount,
        uint256 randStakeToken
    ) public {
        uint256 offset = 10;

        address stakeToken = stakeTokens[randStakeToken % stakeTokens.length];

        address xToken = stakeTokens[(randStakeToken + 1) % stakeTokens.length];
        uint256 xTokenBalance = hexOneStakingWrap.totalStakedAmount(xToken);
        uint256 xTokenWeight = hexOneStakingWrap.stakeTokenWeights(xToken);

        address yToken = stakeTokens[(randStakeToken + 2) % stakeTokens.length];
        uint256 yTokenBalance = hexOneStakingWrap.totalStakedAmount(yToken);
        uint256 yTokenWeight = hexOneStakingWrap.stakeTokenWeights(yToken);

        uint256 stakeAmount = (randAmount % initialMint) / 1000 + 1;
        uint256 shares = calculateShares(stakeToken, stakeAmount);

        if (shares > 0) {
            uint256 stakeTokenBalance = hexOneStakingWrap.totalStakedAmount(stakeToken);
            uint256 stakeTokenBalanceIncreaseFactor = ((stakeAmount + stakeTokenBalance) * 10_000) / stakeTokenBalance;

            (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(hexit));

            uint256 stakeTokenTotalShares =
                totalShares - (xTokenBalance * xTokenWeight) - (yTokenBalance * yTokenWeight);
            uint256 hexSharesIncreaseFactor = ((shares + stakeTokenTotalShares) * 10_000) / stakeTokenTotalShares;

            // emit LogUint(stakeTokenBalanceIncreaseFactor);
            // emit LogUint(hexSharesIncreaseFactor);

            assert(
                stakeTokenBalanceIncreaseFactor >= hexSharesIncreaseFactor - offset
                    && stakeTokenBalanceIncreaseFactor <= hexSharesIncreaseFactor + offset
            );
        }
    }

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
    function setPrices(address tokenIn, address tokenOut, uint256 r) public {
        routerMock.setRate(tokenIn, tokenOut, r);
        hexOnePriceFeedMock.setRate(tokenIn, tokenOut, r);

        uint256 rReversed = 10000 * 10000 / r;
        routerMock.setRate(tokenOut, tokenIn, rReversed);
        hexOnePriceFeedMock.setRate(tokenOut, tokenIn, rReversed);
    }

    function calculateShares(address _stakeToken, uint256 _amount) public returns (uint256) {
        uint256 shares = (_amount * hexOneStakingWrap.stakeTokenWeights(_stakeToken)) / 1000;
        return convertToShares(_stakeToken, shares);
    }

    function convertToShares(address _token, uint256 _amount) public returns (uint256) {
        uint8 decimals = TokenUtils.expectDecimals(_token);
        if (decimals >= 18) {
            return _amount / (10 ** (decimals - 18));
        } else {
            return _amount * (10 ** (18 - decimals));
        }
    }
}
