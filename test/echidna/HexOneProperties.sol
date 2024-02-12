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

    /// ----- HexOneVault -----
    event LogUint(uint256);

    function randDeposit(uint256 randUser, uint256 randAmount, uint16 randDuration) public {
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
        uint256 rate = hexOnePriceFeedMock.getRate(address(hexx), address(hex1));

        uint256 convertedRatio = (totalAmount * rate) - totalBorrowed;

        require(convertedRatio != 0);

        uint256 amount = clampBetween(randAmount, 1, convertedRatio);
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

    function randClaimSacrifice(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

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

        require(r > 0);

        setPrices(tokenIn, tokenOut, uint256(r));
    }

    function randIncreaseTimestamp(uint8 randTs) public {
        hevm.warp(block.timestamp + randTs * 1 days); // add between 1 day and 255 days to timestamps
    }

    // ---------------------- Invariants ---------------------- (Here we will be defining all our invariants)

    /*
    /// @custom:invariant - HEXIT token emmission should never be more than the max emission.
    function hexitEmissionIntegrity() public {}

    function hexOneStakingDailyRewardsCannotExceed1Percent() public {
        uint256 rewardShareMinThreshold = 95;
        uint256 rewardShareMaxThreshold = 105;

        (uint256 hexitTotalAssets, uint256 hexitDistributedAssets,, uint256 hexitCurrentStakingDay,) =
            hexOneStakingWrap.pools(address(hexit));
        uint256 hexitPoolLastSync = hexitCurrentStakingDay;
        (, uint256 hexitAmountToDistribute) = hexOneStakingWrap.poolHistory(hexitPoolLastSync, address(hexit));
        uint256 hexitRewards = hexitAmountToDistribute;
        uint256 hexitAvailable = hexitTotalAssets - hexitDistributedAssets;
        uint256 hexitRewardShare = (hexitRewards * 10_000) / hexitAvailable;

        // Pool hexPool = hexOneStakingWrap.pools(address(hexx));
        // uint256 hexxPoolLastSync = hexPool.currentStakingDay;
        // PoolHistory hexxPoolHistory = hexOneStakingWrap.poolHistory(hexxPoolLastSync, address(hexx));
        // uint256 hexxRewards = hexxPoolHistory.amountToDistribute;
        // uint256 hexxAvailable = hexPool.totalAssets - hexPool.distributedAssets;
        // uint256 hexxRewardShare = (hexxRewards * 10_000) / hexxAvailable;

        assert(hexitRewardShare >= rewardShareMinThreshold && hexitRewardShare <= rewardShareMaxThreshold);
        // assert(hexxRewardShare >= rewardShareMinThreshold && hexxRewardShare <= rewardShareMaxThreshold);
    }

    // function hexOneStakingSharesToGiveAlwaysProportionalToIncreaseInBalance(
    //     uint256 randAmount,
    //     uint256 randStakeToken
    // ) {
    //     uint256 offset = 100;

    //     address token = stakeTokens[randStakeToken % stakeTokens.length];
    //     uint256 amount = (randAmount % initialMint) / 1000 + 1;
    //     uint256 shares = calculateShares(token, amount);

    //     uint256 tokenStakingBalance = hexOneStakingWrap.totalStakedAmount(token);
    //     uint256 tokenBalanceIncreaseFactor = ((amount + tokenStakingBalance) * 10_000) / tokenStakingBalance;

    //     Pool hexPool = hexOneStakingWrap.pools(address(hexx));
    //     uint256 hexTotalShares = hexPool.totalShares;
    //     uint256 hexSharesIncreaseFactor = ((shares + hexTotalShares) * 10_000) / hexTotalShares;

    //     Pool hexitPool = hexOneStakingWrap.pools(address(hexit));
    //     uint256 hexitTotalShares = hexitPool.totalShares;
    //     uint256 hexitSharesIncreaseFactor = ((shares + hexitTotalShares) * 10_000) / hexitTotalShares;

    //     assert(
    //         tokenBalanceIncreaseFactor >= hexSharesIncreaseFactor - offset
    //             && tokenBalanceIncreaseFactor <= hexSharesIncreaseFactor + offset
    //     );
    //     assert(
    //         tokenBalanceIncreaseFactor >= hexitSharesIncreaseFactor - offset
    //             && tokenBalanceIncreaseFactor <= hexitSharesIncreaseFactor + offset
    //     );
    // }
    */

    /// ----- HexOneVault -----

    /// @custom:invariant - Vault deposit must never be claimed if maturity has not passed
    function tryClaimVaultBeforeMaturity(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        (,,,, uint16 duration,) = hexOneVault.depositInfos(address(user), stakeId);
        (bool success,) = user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.claim.selector, stakeId));
        assert(success == false && block.timestamp < duration * 86400);
    }

    /// @custom:invariant - Amount and duration on deposit must always be corresponding to the amount minus fee and corresponding set lock on the contract storage
    /// @custom:invariant - The fee taken from deposits must always be 5%
    function hexOneDepositAmountDurationIntegrity(uint256 randUser, uint256 randAmount, uint256 randDuration) public {
        User user = users[randUser % users.length];

        uint256 amount = clampBetween(randAmount, 1, initialMintHex / 4);
        uint16 duration = uint16(clampBetween(randDuration, hexOneVault.MIN_DURATION(), hexOneVault.MAX_DURATION()));

        emit LogUint(duration);

        uint16 fee = 50;
        uint16 fixed_point = 1000;
        uint256 finalAmount = amount - ((amount * fee) / fixed_point);

        (bool success, bytes memory data) =
            user.proxy(address(hexOneVault), abi.encodeWithSignature("deposit(uint256,uint16)", amount, duration));
        require(success);

        (, uint256 stakeId) = abi.decode(data, (uint256, uint256));

        userToStakeids[user].push(stakeId);

        (uint256 vaultAmount,,,, uint16 vaultDuration,) = hexOneVault.depositInfos(address(user), stakeId);

        assert(success == true && finalAmount == vaultAmount && duration == vaultDuration);
    }

    /// @custom:invariant - If hexOneBorrowed gt 0, the same amount of hexOneBorrowed must always be burned on claim
    /// @custom:invariant - The amount to withdraw after maturity must always be greater or equal than the HEX collateral deposited
    function hexOneBorrowAmountIntegrity(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        (uint256 vaultAmount,,,,,) = hexOneVault.depositInfos(address(user), stakeId);

        (bool success, bytes memory data) =
            user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.claim.selector, stakeId));
        require(success);

        uint256 hexAmount = abi.decode(data, (uint256));
        (,, uint256 vaultBorrowedAfter,,,) = hexOneVault.depositInfos(address(user), stakeId);
        uint256 userHexoneBalanceAfter = hex1.balanceOf(address(user));

        assert(hexAmount >= vaultAmount);
        assert(vaultBorrowedAfter == 0 && userHexoneBalanceAfter == 0);
    }

    /*
    /// @custom:invariant - Must only be able to mint more HEXONE with the same HEX collateral if the HEX price increases
    function tryMintMorePriceIncrease(uint256 randUser, uint256 randAmount, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 amount = (randAmount % 1 ether); // this can be improved
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];
        (bool success,) =
            user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.borrow.selector, amount, stakeId));
        require(success);
    }
    */

    /// @custom:invariant - The sum of all `DepositInfo.amount` HEX deposited by the user across all its deposits must always be equal to `UserInfo.totalAmount`
    function checkDepositUserInfoIntegrity(uint256 randUser) public {
        User user = users[randUser % users.length];
        uint256 depositTotalAmount;

        for (uint256 i = 0; i < userToStakeids[user].length; i++) {
            (uint256 depositAmount,,,,,) = hexOneVault.depositInfos(address(user), userToStakeids[user][i]);
            depositTotalAmount += depositAmount;
        }

        (uint256 userTotalAmount,,) = hexOneVault.userInfos(address(user));

        assert(depositTotalAmount == userTotalAmount);
    }

    /// @custom:invariant - The sum of all `DepositInfo.borrowed` HEX1 borrowed by the user across all its deposits must always be equal to `UserInfo.totalBorrowed`
    function checkBorrowUserInfoIntegrity(uint256 randUser) public {
        User user = users[randUser % users.length];
        uint256 depositTotalBorrowed;

        for (uint256 i = 0; i < userToStakeids[user].length; i++) {
            (,, uint256 depositBorrowed,,,) = hexOneVault.depositInfos(address(user), userToStakeids[user][i]);
            depositTotalBorrowed += depositBorrowed;
        }

        (,, uint256 userTotalBorrowed) = hexOneVault.userInfos(address(user));

        assert(depositTotalBorrowed == userTotalBorrowed);
    }

    /// @custom:invariant - HEX1 minted must always be equal to the total amount of HEX1 needed to claim or liquidate all deposits
    function hexOneLiquidationsIntegrity() public {
        uint256 totalHexoneUsersAmount;
        uint256 totalHexoneProtocolAmount;

        for (uint256 i = 0; i < totalNbUsers; i++) {
            (,, uint256 totalBorrowed) = hexOneVault.userInfos(address(users[i]));
            totalHexoneProtocolAmount += totalBorrowed;
        }

        for (uint256 i = 0; i < totalNbUsers; i++) {
            totalHexoneUsersAmount += hex1.balanceOf(address(users[i]));
        }

        assert(totalHexoneUsersAmount == totalHexoneProtocolAmount);
    }

    /// @custom:invariant - staking history.amountToDistribute for a given day must always be == 0 whenever pool.totalShares is also == 0
    function poolAmountStateIntegrity() public {
        for (uint256 i = 0; i < stakeTokens.length; i++) {
            (,,, uint256 currentStakingDay,) = hexOneStakingWrap.pools(address(stakeTokens[i]));
            (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(stakeTokens[i]));
            (, uint256 amountToDistribute) = hexOneStakingWrap.poolHistory(currentStakingDay, address(stakeTokens[i]));

            if (totalShares == 0 || amountToDistribute == 0) {
                assert(totalShares == amountToDistribute);
            }
        }
    }

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
