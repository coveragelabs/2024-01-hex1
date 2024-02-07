// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../src/HexOneStaking.sol";
import "../../src/HexitToken.sol";
import "../../src/HexOneBootstrap.sol";
import "../../src/HexOneVault.sol";
import "./mocks/ERC20Mock.sol";
import "./mocks/hexOnePriceFeedMock.sol";
import "./mocks/DexRouterMock.sol";
import "./mocks/DexFactoryMock.sol";
import "./mocks/HexMockToken.sol";
import "./wraps/HexitTokenWrap.sol";
import "./wraps/Hex1TokenWrap.sol";

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
    User[] public users;

    // contracts
    HexitTokenWrap public hexit;
    HexOneBootstrap public hexOneBootstrap;
    HexOneStaking public hexOneStaking;
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
        hexOneStaking = new HexOneStaking(address(hexx), address(hexit), hexDistRate, hexitDistRate);
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

        address[] memory stakeTokens = new address[](3); // prepare the allowed staking tokens
        stakeTokens[0] = address(dai);
        stakeTokens[1] = address(hex1);
        stakeTokens[2] = address(hexit);
        uint16[] memory weights = new uint16[](3); // prepare the distribution weights for each stake token
        weights[0] = 700;
        weights[1] = 200;
        weights[2] = 100;
        address[] memory sacrificeTokens = new address[](2);
        sacrificeTokens[0] = address(hexx);
        sacrificeTokens[1] = address(dai);
        uint16[] memory multipliers = new uint16[](2); // create an array with the corresponding multiplier for each sacrifice token
        multipliers[0] = 5555;
        multipliers[1] = 3000;

        hex1.setHexOneVault(address(hexOneVault));
        hexit.setHexOneBootstrap(address(hexOneBootstrap));
        hexOneStaking.setBaseData(address(hexOneVault), address(hexOneBootstrap));
        hexOneStaking.setStakeTokens(stakeTokens, weights);
        hexOneVault.setBaseData(address(hexOnePriceFeedMock), address(hexOneStaking), address(hexOneBootstrap));
        hexOneBootstrap.setBaseData(address(hexOnePriceFeedMock), address(hexOneStaking), address(hexOneVault));
        hexOneBootstrap.setSacrificeTokens(sacrificeTokens, multipliers);
        hexOneBootstrap.setSacrificeStart(block.timestamp);

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
            hexx.mint(address(user), 100 ether);
            dai.mint(address(user), 100 ether);
        }
    }

    // --------------------- State updates --------------------- (Here we will be defining all state update functions)

    /// ----- HexOneVault -----
    function randDeposit(uint256 randUser, uint256 randAmount, uint256 randDuration) public {}
    function randClaim(uint256 randUser, uint256 randStakeId) public {}
    function randBorrow(uint256 randUser, uint256 randAmount, uint256 randStakeId) public {}
    function randLiquidate(uint256 randUser, address randDepositor, uint256 randStakeId) public {}
    /// ----- HexOneVault -----

    function randStake(uint256 randUser, uint256 randAmount, address randStakeToken) public {}
    function randUnstake(uint256 randUser, uint256 randAmount, address randStakeToken) public {}
    function randClaim(uint256 randUser, address randStakeToken) public {}
    /// ----- HexOneVault -----
    function randSacrifice(uint256 randUser, address randToken, uint256 randAmountIn, uint256 randAmountOutMin)
        public
    {}
    function randClaimSacrifice(uint256 randUser) public {}
    function randClaimAirdrop(uint256 randUser) public {}

    // ---------------------- Invariants ---------------------- (Here we will be defining all our invariants)

    /// @custom:invariant - HEXIT token emmission should never be more than the max emission.
    function hexitEmissionIntegrity() public {}

    // ---------------------- Helpers ------------------------- (Free area to define helper functions)
    function setPrices(address tokenIn, address tokenOut, uint256 r) public {
        routerMock.setRate(tokenIn, tokenOut, r);
        hexOnePriceFeedMock.setRate(tokenIn, tokenOut, r);

        uint256 rReversed = 10000 * 10000 / r;
        routerMock.setRate(tokenOut, tokenIn, rReversed);
        hexOnePriceFeedMock.setRate(tokenOut, tokenIn, rReversed);
    }
}
