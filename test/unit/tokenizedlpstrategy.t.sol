// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy, IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockTokenizedStrategy} from "test/unit/mocks/yearn/MockTokenizedStrategy.sol";
import {Provider} from "src/module/Provider.sol";
import {ICurveLpConnector} from "src/interface/ICurveLpConnector.sol";
import {MockConnector} from "test/unit/mocks/MockConnector.sol";

contract TokenizedLPStrategyUnitTest is Test, MainnetActors, Etches {
    MockTokenizedStrategy public strategy;
    Vault public vault;
    WETH9 public lpToken;
    Provider public provider;
    MockConnector public connector;
    uint256 public constant INITIAL_BALANCE = 101 ether;
    uint256 public constant MOCK_RATE = 1.2 ether;

    function setUp() public {
        vm.warp(10 hours);

        SetupVault setup = new SetupVault();
        (vault, lpToken) = setup.setup(true);
        string memory name = "MockTokenizedStrategy";
        string memory symbol = "MTS";

        // etch strategy
        MockTokenizedStrategy strategy_ = new MockTokenizedStrategy();
        vm.etch(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, address(strategy_).code);

        strategy = MockTokenizedStrategy(payable(address(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY)));
        strategy.initialize(MC.CURVE_LP_YNETH_YNLSDE_POOL, name, ADMIN, ADMIN, ADMIN);

        lpToken = WETH9(payable(MC.CURVE_LP_YNETH_YNLSDE_POOL));
        vm.deal(address(vault), INITIAL_BALANCE);
        vm.startPrank(address(vault));
        lpToken.deposit{value: INITIAL_BALANCE}();
        lpToken.transfer(address(vault), INITIAL_BALANCE);

        vm.label(address(lpToken), "lp token");
        vm.label(address(strategy), "strategy");
        vm.label(address(vault), "vault");

        connector = MockConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);

        connector.setTimeStamp(block.timestamp);
        connector.setRate(int256(MOCK_RATE));
        (int256 rate, uint256 timestamp) = connector.rate();
        assertEq(uint256(rate), MOCK_RATE, "Connector rate should be set correctly");
        assertEq(timestamp, block.timestamp, "Connector timestamp should be set correctly");

        configureVault();
    }

    function configureVault() public {
        vm.startPrank(ADMIN);
        vault.addAsset(address(strategy), false);
        vm.stopPrank();
    }

    function test_processAccounting() public {
        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);

        vault.processAccounting();

        uint256 expectedBaseValue = (strategyBalance * MOCK_RATE) / 1e18;
        assertEq(vault.totalAssets(), expectedBaseValue, "Vault should account strategy value correctly");
    }

    function test_strategyRateReverts_whenStale() public {
        vm.warp(block.timestamp + 10 hours);

        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);

        vm.expectRevert(Provider.RateIsStale.selector);
        vault.processAccounting();
    }
}
