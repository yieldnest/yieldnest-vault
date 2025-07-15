// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISuperUSDC} from "src/interface/ISuperUSDC.sol";
import {IMorpho, MarketParams, Id} from "test/interface/external/morpho/IMorpho.sol";

contract SuperUSDCTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        vm.stopPrank();
        bufferStrategy = MC.MORPHO_GAUNTLET_USDC_VAULT;
    }

    function test_morpho_gauntlet_isolated_usdc_vault() public {
        address MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        IMorpho morpho = IMorpho(MORPHO);

        bytes32 MARKET_ID = 0x98809e0a4fb92b7d7def2a2a49bbe7bdacdf70cbcf53a04b765cf1afbf45b013;

        MarketParams memory marketParams = morpho.idToMarketParams(Id.wrap(MARKET_ID));

        address alice = makeAddr("alice");
        deal(USDC, alice, 1000e6);
        vm.startPrank(alice);
        IERC20(USDC).approve(MORPHO, 1000e6);
        (, uint256 sharesSupplied) = morpho.supply(marketParams, 1000e6, 0, alice, "");
        console.log("sharesSupplied", sharesSupplied);

        morpho.withdraw(marketParams, 0, sharesSupplied, alice, alice);

        vm.stopPrank();

        assertEq(0, morpho.position(Id.wrap(MARKET_ID), alice).supplyShares);
    }
}
