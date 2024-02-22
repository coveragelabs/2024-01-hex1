// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Test, stdError, console2 as console} from "forge-std/Test.sol";

import {HexOneToken} from "../../src/HexOneToken.sol";
import {HexitToken} from "../../src/HexitToken.sol";
import {HexOneStaking} from "../../src/HexOneStaking.sol";
import {HexOneVault} from "../../src/HexOneVault.sol";
import {HexOneBootstrap} from "../../src/HexOneBootstrap.sol";

import {HexOnePriceFeedMock} from "./utils/HexOnePriceFeedMock.sol";
import {HexTokenMock} from "./utils/HexTokenMock.sol";
import {DaiTokenMock} from "./utils/DaiTokenMock.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultBase is Test {
    HexOneToken public hex1;
    HexitToken public hexit;
    HexOneVault public vault;
    HexOneStaking public staking;

    HexOnePriceFeedMock public feed;
    DaiTokenMock public daiToken;

    HexTokenMock public hexToken;

    address public bootstrap = makeAddr("HexOneBootstrap");

    address public user = makeAddr("user");
    address public deployer = makeAddr("deployer");
    address public receiver = makeAddr("receiver");

    function setUp() public virtual {
        vm.startPrank(deployer);

        // deploy DAI token mock
        daiToken = new DaiTokenMock();

        // deploy HEX token mock
        hexToken = new HexTokenMock();

        // deploy HEX1 token
        hex1 = new HexOneToken("Hex One Token", "HEX1");

        // deploy HEXIT token
        hexit = new HexitToken("Hexit Token", "HEXIT");

        // deploy the price feed mock
        feed = new HexOnePriceFeedMock();

        // deploy the vault
        vault = new HexOneVault(address(hexToken), address(daiToken), address(hex1));

        // deploy the staking contract
        staking = new HexOneStaking(address(hexToken), address(hexit), 100, 100);

        // set the vault to have permissions to mint HEX1
        hex1.setHexOneVault(address(vault));

        // set the bootstrap to have permissions to mint HEXIT
        hexit.setHexOneBootstrap(address(bootstrap));

        // set HEX/DAI rate in the price feed mock
        feed.setRate(address(hexToken), address(daiToken), 15275940385037058);

        // configure the vault
        vault.setBaseData(address(feed), address(staking), bootstrap);

        // configure the staking contract
        staking.setBaseData(address(vault), bootstrap);

        vm.stopPrank();
    }
}
