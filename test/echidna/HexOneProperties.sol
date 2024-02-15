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

    //team wallet
    User private teamWallet;

    constructor() {
        // config -----------
        totalNbUsers = 10;

        initialMintHex = 100000000e8;
        initialMintToken = 100000000 ether;

        uint16 hexDistRate = 10;
        uint16 hexitDistRate = 10;
        // ------------------
        teamWallet = new User();

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

        uint256 amount = clampBetween(randAmount, 1, initialMintHex / 100);
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

        uint256 convertedRatio = (totalAmount * (rate / 1e18)) - totalBorrowed;

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
        uint256 amount = clampBetween(randAmount, 1, initialMintToken / 100);

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

        uint256 amount =
            clampBetween(randAmountIn, 1, (token == address(hexx) ? initialMintHex : initialMintToken) / 100);

        (bool success,) = user.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(success);
    }

    function randClaimSacrifice(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success, bytes memory data) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));
        require(success);

        (uint256 stakeId,,) = abi.decode(data, (uint256, uint256, uint256));

        userToStakeids[user].push(stakeId);
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

        uint256 amount = clampBetween(randAmount, 1, initialMintHex / 100);
        uint16 duration = uint16(clampBetween(randDuration, hexOneVault.MIN_DURATION(), hexOneVault.MAX_DURATION()));

        emit LogUint(duration);

        uint16 fee = 50;
        uint16 fixed_point = 1000;
        uint256 finalAmount = amount - ((amount * fee) / fixed_point);

        (bool success, bytes memory data) =
            user.proxy(address(hexOneVault), abi.encodeWithSignature("deposit(uint256,uint16)", amount, duration));

        (, uint256 stakeId) = abi.decode(data, (uint256, uint256));

        userToStakeids[user].push(stakeId);

        (uint256 vaultAmount,,,, uint16 vaultDuration,) = hexOneVault.depositInfos(address(user), stakeId);

        assert(finalAmount == vaultAmount && duration == vaultDuration);
    }

    /// @custom:invariant - If hexOneBorrowed gt 0, the same amount of hexOneBorrowed must always be burned on claim
    /// @custom:invariant - The amount to withdraw after maturity must always be greater or equal than the HEX collateral deposited
    function hexOneBorrowAmountIntegrity(uint256 randUser, uint256 randStakeId, uint256 randTimestamp) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];
        (uint256 vaultAmount,,,, uint16 duration,) = hexOneVault.depositInfos(address(user), stakeId);

        hevm.warp(block.timestamp + duration * 86400 + clampBetween(randTimestamp, 1, 604800));

        (bool success, bytes memory data) =
            user.proxy(address(hexOneVault), abi.encodeWithSelector(hexOneVault.claim.selector, stakeId));

        uint256 hexAmount = abi.decode(data, (uint256));
        (,, uint256 vaultBorrowedAfter,,,) = hexOneVault.depositInfos(address(user), stakeId);
        uint256 userHexoneBalanceAfter = hex1.balanceOf(address(user));

        assert(hexAmount >= vaultAmount);
        assert(vaultBorrowedAfter == 0 && userHexoneBalanceAfter == 0);
    }

    /// @custom:invariant - Must only be able to mint more HEXONE with the same HEX collateral if the HEX price increases
    // @audit-issue - Misleading name in internal quote function (INFO)
    function tryMintMorePriceIncrease(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        (uint256 totalAmount,, uint256 totalBorrowed) = hexOneVault.userInfos(address(user));

        uint256 rate = hexOnePriceFeedMock.getRate(address(hexx), address(dai));
        setPrices(address(hexx), address(dai), rate * 2);
        uint256 convertedRatio = (totalAmount * ((rate * 2) / 1e18)) - totalBorrowed;

        require(convertedRatio != 0);

        (bool success,) = user.proxy(
            address(hexOneVault), abi.encodeWithSelector(hexOneVault.borrow.selector, convertedRatio, stakeId)
        );

        (,, uint256 newTotalBorrowed) = hexOneVault.userInfos(address(user));

        uint256 oldBalance = hex1.balanceOf(address(user));
        setPrices(address(hexx), address(dai), rate * 4);

        uint256 newRate = hexOnePriceFeedMock.getRate(address(hexx), address(dai));
        uint256 newConvertedRatio = (totalAmount * ((newRate * 2) / 1e18)) - newTotalBorrowed;

        (bool success1,) = user.proxy(
            address(hexOneVault), abi.encodeWithSelector(hexOneVault.borrow.selector, newConvertedRatio, stakeId)
        );

        uint256 newBalance = hex1.balanceOf(address(user));

        assert(newBalance > oldBalance);
    }

    /// @custom:invariant - Must never be able to mint more HEXONE with the same HEX collateral if the HEX price decreases
    function tryMintMorePriceDecrease(uint256 randUser, uint256 randStakeId) public {
        User user = users[randUser % users.length];
        uint256 stakeId = userToStakeids[user][randStakeId % userToStakeids[user].length];

        (uint256 totalAmount,, uint256 totalBorrowed) = hexOneVault.userInfos(address(user));

        uint256 rate = hexOnePriceFeedMock.getRate(address(hexx), address(dai));
        setPrices(address(hexx), address(dai), rate / 2);
        uint256 convertedRatio = (totalAmount * ((rate / 2) / 1e18)) - totalBorrowed;

        uint256 oldBalance = hex1.balanceOf(address(user));

        (bool success,) = user.proxy(
            address(hexOneVault), abi.encodeWithSelector(hexOneVault.borrow.selector, convertedRatio, stakeId)
        );

        uint256 newBalance = hex1.balanceOf(address(user));

        assert(newBalance == oldBalance);
    }

    /// @custom:invariant - The sum of all `DepositInfo.amount` HEX deposited by the user across all its deposits must always be equal to `UserInfo.totalAmount`
    function checkDepositUserInfoIntegrity(uint256 randUser) public {
        User user = users[randUser % users.length];
        uint256 depositTotalAmount = 0;

        for (uint256 i = 0; i < userToStakeids[user].length; i++) {
            (uint256 depositAmount,,,,,) = hexOneVault.depositInfos(address(user), userToStakeids[user][i]);
            depositTotalAmount += depositAmount;
        }

        (uint256 userTotalAmount,,) = hexOneVault.userInfos(address(user));

        emit LogUint(depositTotalAmount);
        emit LogUint(userTotalAmount);
        assert(depositTotalAmount == userTotalAmount);
    }

    /// @custom:invariant - The sum of all `DepositInfo.borrowed` HEX1 borrowed by the user across all its deposits must always be equal to `UserInfo.totalBorrowed`
    function checkBorrowUserInfoIntegrity(uint256 randUser) public {
        User user = users[randUser % users.length];
        uint256 depositTotalBorrowed = 0;

        for (uint256 i = 0; i < userToStakeids[user].length; i++) {
            (,, uint256 depositBorrowed,,,) = hexOneVault.depositInfos(address(user), userToStakeids[user][i]);
            depositTotalBorrowed += depositBorrowed;
        }

        (,, uint256 userTotalBorrowed) = hexOneVault.userInfos(address(user));

        emit LogUint(depositTotalBorrowed);
        emit LogUint(userTotalBorrowed);
        assert(depositTotalBorrowed == userTotalBorrowed);
    }

    /// @custom:invariant - HEX1 minted must always be equal to the total amount of HEX1 needed to claim or liquidate all deposits
    // @audit:issue - Invariant broken (LOW accounting issue below 1e14 $HEX1)
    function hexOneLiquidationsIntegrity() public {
        uint256 totalHexoneUsersAmount;
        uint256 totalHexoneProtocolAmount;

        for (uint256 i = 0; i < totalNbUsers; i++) {
            (,, uint256 totalBorrowed) = hexOneVault.userInfos(address(users[i]));
            totalHexoneProtocolAmount += totalBorrowed;
            totalHexoneUsersAmount += hex1.balanceOf(address(users[i]));
        }

        require(totalHexoneUsersAmount != 0 && totalHexoneProtocolAmount != 0 /*&& totalHexoneUsersAmount > 1e14*/ );

        emit LogUint(totalHexoneUsersAmount);
        emit LogUint(totalHexoneProtocolAmount);
        assert(totalHexoneUsersAmount >= totalHexoneProtocolAmount);
    }

    /*
    /// @custom:invariant - staking history.amountToDistribute for a given day must always be == 0 whenever pool.totalShares is also == 0
    // @audit-issue - Invariant broken (MEDIUM accounting issue)
    function poolAmountStateIntegrity() public {
        for (uint256 i = 0; i < stakeTokens.length; i++) {
            (,,, uint256 currentStakingDay,) = hexOneStakingWrap.pools(address(stakeTokens[i]));
            (,, uint256 totalShares,,) = hexOneStakingWrap.pools(address(stakeTokens[i]));
            (, uint256 amountToDistribute) = hexOneStakingWrap.poolHistory(currentStakingDay, address(stakeTokens[i]));

            if (totalShares == 0) {
                assert(totalShares == amountToDistribute);
            }
        }
    }
    */

    /// ----- HexOneBootstrap -----

    /// @custom:invariant - If two users sacrificed the same amount of the same sacrifice token on different days, the one who sacrificed first should always receive more `HEXIT` (different days)
    /// @custom:invariant The amount of `UserInfo.hexitShares` a user has must always be equal to the amount of `HEXIT` minted when the user claim its sacrifice rewards via `claimSacrifice` function
    function sacrificePriorityAndSharesIntegrity(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, initialMintToken / 100);

        (bool success, bytes memory dataSacrifice) = user.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (uint256 stakeId,,) = abi.decode(dataSacrifice, (uint256, uint256, uint256));

        userToStakeids[user].push(stakeId);

        hevm.warp(block.timestamp + 86401);

        (bool success1, bytes memory dataSacrifice1) = newUser.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (uint256 stakeId1,,) = abi.decode(dataSacrifice1, (uint256, uint256, uint256));

        userToStakeids[newUser].push(stakeId1);

        hevm.prank(address(0x10000));
        hexOneBootstrap.processSacrifice(1);

        hevm.warp(block.timestamp + 86401);

        (bool successSacrifice, bytes memory data) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));

        (,, uint256 hexitMinted) = abi.decode(data, (uint256, uint256, uint256));

        (uint256 hexitShares,,,) = hexOneBootstrap.userInfos(address(user));

        assert(hexitMinted == hexitShares);

        (bool successSacrifice1, bytes memory data1) =
            newUser.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));

        (,, uint256 hexitMinted1) = abi.decode(data1, (uint256, uint256, uint256));

        assert(hexitMinted > hexitMinted1);
    }

    /// @custom:invariant If two users are entitled to the same amount of airdrop (HEX staked in USD + sacrificed USD), the one who claimed first should always receive more `HEXIT` (different days)
    function airdropPriorityIntegrityDifferentDays(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, initialMintToken / 100);

        (bool success,) = user.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (bool success1,) = newUser.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        hevm.prank(address(0x10000));
        hexOneBootstrap.processSacrifice(1);

        (bool successSacrifice,) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));

        (bool successSacrifice1,) =
            newUser.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));

        uint256 oldUserBalance = hexit.balanceOf(address(user));
        uint256 oldNewUserBalance = hexit.balanceOf(address(newUser));

        hevm.warp(block.timestamp + 86401);

        hevm.prank(address(0x10000));
        hexOneBootstrap.startAidrop();

        (bool successAirdrop,) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimAirdrop.selector));

        hevm.warp(block.timestamp + 86401);

        (bool successAirdrop1,) =
            newUser.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimAirdrop.selector));

        uint256 newUserBalance = hexit.balanceOf(address(newUser));
        uint256 newNewUserBalance = hexit.balanceOf(address(newUser));

        uint256 finalUserBalance = newUserBalance - oldUserBalance;
        uint256 finalNewUserBalance = newNewUserBalance - oldNewUserBalance;

        assert(finalUserBalance > finalNewUserBalance);
    }

    /// @custom:invariant If two users are entitled to the same amount of airdrop (HEX staked in USD + sacrificed USD), they should always receive the same amount of `HEXIT` if they claimed the airdrop on the same day
    function airdropPriorityIntegritySameDay(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, initialMintToken / 100);

        (bool success,) = user.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (bool success1,) = newUser.proxy(
            address(hexOneBootstrap),
            abi.encodeWithSelector(hexOneBootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        hevm.prank(address(0x10000));
        hexOneBootstrap.processSacrifice(1);

        (bool successSacrifice,) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));

        (bool successSacrifice1,) =
            newUser.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimSacrifice.selector));

        uint256 oldUserBalance = hexit.balanceOf(address(user));
        uint256 oldNewUserBalance = hexit.balanceOf(address(newUser));

        hevm.warp(block.timestamp + 86401);

        hevm.prank(address(0x10000));
        hexOneBootstrap.startAidrop();

        (bool successAirdrop,) =
            user.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimAirdrop.selector));

        (bool successAirdrop1,) =
            newUser.proxy(address(hexOneBootstrap), abi.encodeWithSelector(hexOneBootstrap.claimAirdrop.selector));

        uint256 newUserBalance = hexit.balanceOf(address(newUser));
        uint256 newNewUserBalance = hexit.balanceOf(address(newUser));

        uint256 finalUserBalance = newUserBalance - oldUserBalance;
        uint256 finalNewUserBalance = newNewUserBalance - oldNewUserBalance;

        assert(finalUserBalance == finalNewUserBalance);
    }

    /*
    /// @custom:invariant - The `startAirdrop` function must always mint 33% on top of the total `HEXIT` minted during the sacrifice phase to the HexOneStaking contract
    /// @custom:invariant - The `startAirdrop` function must always mint 50% on top of the total `HEXIT` minted during the sacrifice phase to the team wallet
    // @audit-issue - Invariants broken (LOW architectural issue)
    function airdropMintingIntegrity() public {
        uint256 totalHexitMinted = hexOneBootstrap.totalHexitMinted();
        uint256 stakingContractBalance = hexit.balanceOf(address(hexOneStakingWrap));
        uint256 teamWalletBalance = hexit.balanceOf(address(teamWallet));

        require(stakingContractBalance != 0 && teamWalletBalance != 0);

        emit LogUint(totalHexitMinted);
        emit LogUint(stakingContractBalance);
        emit LogUint(teamWalletBalance);

        assert(stakingContractBalance == (totalHexitMinted * 33) / 100);
        assert(teamWalletBalance == (totalHexitMinted * 50) / 100);
    }
    */

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
