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
import {ICurvePool} from "test/interface/external/curve/ICurvePool.sol";
import {MockConnector} from "test/mainnet/mocks/MockConnector.sol";
import {ConnectorRules} from "script/ConnectorRules.sol";
import {BaseRules} from "script/BaseRules.sol";

contract TokenizedLPStrategyUnitTest is Test, MainnetActors, Etches, ConnectorRules, BaseRules {
    MockTokenizedStrategy public strategy;
    Vault public vault;
    WETH9 public lpToken;
    address public buffer = address(0x45c3B59d53e2e148Aaa6a857521059676D5c0489);
    Provider public provider;
    MockConnector public connector;

    uint256 public constant INITIAL_BALANCE = 101 ether;
    uint256 public constant MOCK_RATE = 1.2 ether;

    address public constant ASSET_A = MC.YNETH;
    address public constant ASSET_B = MC.YNLSDE;

    function setUp() public {
        SetupVault setup = new SetupVault();
        (vault, lpToken) = setup.setup();

        string memory name = "MockTokenizedStrategy";
        string memory symbol = "MTS";

        strategy = new MockTokenizedStrategy();
        vm.etch(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, address(strategy).code);
        strategy = MockTokenizedStrategy(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY);
        strategy.initialize(MC.CURVE_LP_YNETH_YNLSDE_POOL, name, ADMIN, ADMIN, ADMIN);
        assertEq(strategy.asset(), MC.CURVE_LP_YNETH_YNLSDE_POOL, "Strategy asset should be set correctly");

        lpToken = new WETH9();
        vm.etch(MC.CURVE_LP_YNETH_YNLSDE_POOL, address(lpToken).code);
        lpToken = WETH9(payable(MC.CURVE_LP_YNETH_YNLSDE_POOL));

        vm.deal(address(vault), INITIAL_BALANCE);

        vm.label(address(lpToken), "lp token");
        vm.label(address(strategy), "strategy");
        vm.label(address(vault), "vault");
        vm.label(buffer, "buffer");
        vm.label(MC.PROVIDER, "provider");

        mockConnector(address(vault), address(strategy), ASSET_A, ASSET_B);

        configureVault();
    }

    function mockConnector(address _vault, address _strategy, address _assetA, address _assetB) public {
        vm.mockCall(
            MC.CURVE_LP_YNETH_YNLSDE_POOL,
            abi.encodeWithSelector(ICurvePool.coins.selector, 0),
            abi.encode(address(_assetA))
        );

        vm.mockCall(
            MC.CURVE_LP_YNETH_YNLSDE_POOL,
            abi.encodeWithSelector(ICurvePool.coins.selector, 1),
            abi.encode(address(_assetB))
        );

        MockConnector connector_ = new MockConnector(_vault, _strategy, _assetA, _assetB);
        vm.etch(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR, address(connector_).code);

        connector = MockConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);

        vm.warp(block.timestamp + 10 hours);
        connector.initialize(block.timestamp, int256(MOCK_RATE));

        (int256 rate, uint256 timestamp) = connector.rate();
        assertEq(uint256(rate), MOCK_RATE, "Connector rate should be set correctly");
        assertEq(timestamp, block.timestamp, "Connector timestamp should be set correctly");
    }

    function configureVault() public {
        vm.startPrank(ADMIN);
        vault.addAsset(address(strategy), true);
        vault.setBuffer(buffer);
        vault.setProvider(MC.PROVIDER);
        setApprovalRule(vault, ASSET_A, address(connector));
        setApprovalRule(vault, ASSET_B, address(connector));
        setConnectorDepositRule(vault, address(connector));
        setConnectorWithdrawRule(vault, address(connector));
        vm.stopPrank();
    }

    function test_processAccounting() public {
        vault.processAccounting();
        uint256 totalAssetsBefore = vault.totalAssets();

        // Test vault accounting
        uint256 strategyBalance = 1e18; // 1 strategy token

        deal(address(strategy), address(vault), strategyBalance);

        vault.processAccounting();

        int256 expectedBaseValue = int256((strategyBalance * uint256(MOCK_RATE)) / 1e18);
        assertEq(
            vault.totalAssets(),
            uint256(int256(totalAssetsBefore) + expectedBaseValue),
            "Vault should account strategy value correctly"
        );
    }

    function test_strategyRateReverts_whenStale() public {
        deal(address(strategy), address(vault), 1 ether);
        connector.setTimeStamp(block.timestamp - 7 hours);
        vm.expectRevert(Provider.RateIsStale.selector);
        vault.processAccounting();
    }

    function test_strategyRateReverts_whenNegative() public {
        deal(address(strategy), address(vault), 1 ether);
        connector.setTimeStamp(block.timestamp - 7 hours);
        connector.setRate(int256(-1 ether));
        vm.expectRevert(Provider.RateIsNegative.selector);
        vault.processAccounting();
    }
}
