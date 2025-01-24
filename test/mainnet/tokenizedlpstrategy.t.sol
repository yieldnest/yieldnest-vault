// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy, IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockTokenizedStrategy} from "test/mainnet/mocks/yearn/MockTokenizedStrategy.sol";
import {Provider} from "src/module/Provider.sol";
import {ICurveLpConnector} from "src/interface/ICurveLpConnector.sol";
import {MockConnector} from "test/mainnet/mocks/MockConnector.sol";
import {ICurvePool} from "src/interface/external/curve/ICurvePool.sol";

contract TokenizedLPStrategyUnitTest is Test, MainnetActors, Etches {
    MockTokenizedStrategy public strategy;
    Vault public vault;
    ICurvePool public pool;
    MockConnector public connector;
    uint256 public constant INITIAL_BALANCE = 101 ether;
    uint256 public constant MOCK_RATE = 1.2 ether;

    function mockConnector(address _vault, address _strategy, address _assetA, address _assetB) public {
        MockConnector connector_ = new MockConnector(_vault, _strategy, _assetA, _assetB);
        vm.etch(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR, address(connector_).code);

        connector = MockConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
        connector.initialize(block.timestamp, int256(MOCK_RATE));

        (int256 rate, uint256 timestamp) = connector.rate();
        assertEq(uint256(rate), MOCK_RATE, "Connector rate should be set correctly");
        assertEq(timestamp, block.timestamp, "Connector timestamp should be set correctly");
    }

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade(false);
        vault = Vault(payable(MC.YNETHX));

        // etch strategy
        MockTokenizedStrategy strategy_ = new MockTokenizedStrategy();
        vm.etch(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, address(strategy_).code);

        strategy = MockTokenizedStrategy(payable(address(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY)));

        // initialize strategy
        string memory name = "MockTokenizedStrategy";
        strategy.initialize(MC.CURVE_LP_YNETH_YNLSDE_POOL, name, ADMIN, ADMIN, ADMIN);

        pool = ICurvePool(payable(MC.CURVE_LP_YNETH_YNLSDE_POOL));

        mockConnector(address(vault), address(strategy), MC.YNETH, MC.YNLSDE);

        vm.label(address(pool), "pool");
        vm.label(address(strategy), "strategy");
        vm.label(address(vault), "vault");

        configureVault();
    }

    function configureVault() public {
        vm.startPrank(ADMIN);
        vault.addAsset(address(strategy), false);
        vm.stopPrank();
    }

    function test_processAccounting() public {
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);

        vault.processAccounting();

        uint256 expectedBaseValue = (strategyBalance * MOCK_RATE) / 1e18;
        assertEq(
            vault.totalAssets(), totalAssetsBefore + expectedBaseValue, "Vault should account strategy value correctly"
        );
    }

    function test_strategyRateReverts_whenStale() public {
        vm.warp(block.timestamp + 10 hours);

        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);

        vm.expectRevert(Provider.RateIsStale.selector);
        vault.processAccounting();
    }
}
