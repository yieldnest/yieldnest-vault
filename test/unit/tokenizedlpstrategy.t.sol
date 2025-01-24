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
    address public buffer = address(0x45c3B59d53e2e148Aaa6a857521059676D5c0489);
    Provider public provider;
    MockConnector public connector;
    uint256 public constant INITIAL_BALANCE = 101 ether;

    function setUp() public {
        SetupVault setup = new SetupVault();
        (vault, lpToken) = setup.setup();
        string memory name = "MockTokenizedStrategy";
        string memory symbol = "MTS";

        strategy = new MockTokenizedStrategy();
        strategy.initialize(MC.CURVE_LP_YNETH_YNLSDE_POOL, name, ADMIN, ADMIN, ADMIN);

        lpToken = WETH9(payable(MC.CURVE_LP_YNETH_YNLSDE_POOL));
        vm.deal(address(vault), INITIAL_BALANCE);
        vm.startPrank(address(vault));
        lpToken.deposit{value: INITIAL_BALANCE}();
        lpToken.transfer(address(vault), INITIAL_BALANCE);

        vm.label(address(lpToken), "lp token");
        vm.label(address(strategy), "strategy");
        vm.label(address(vault), "vault");
        vm.label(buffer, "buffer");
        vm.label(MC.PROVIDER, "provider");

        connector = MockConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);

        connector.setTimeStamp(block.timestamp);
        connector.setRate(1.2 ether);
        (int256 rate, uint256 timestamp) = connector.rate();
        assertEq(rate, 1.2 ether, "Connector rate should be set correctly");
        assertEq(timestamp, block.timestamp, "Connector timestamp should be set correctly");
        configureVault();
    }

    function configureVault() public {
        vm.startPrank(ADMIN);
        vault.addAsset(address(MC.CURVE_LP_YNETH_YNLSDE_POOL), true);
        vault.addAsset(address(strategy), false);
        vault.setBuffer(buffer);
        vault.setProvider(MC.PROVIDER);
        //  vault.unpause();
        vm.stopPrank();
    }

    function test_processAccounting() public {
        vm.warp(block.timestamp + 10 hours);
        // Mock the Curve LP connector rate
        vm.mockCall(
            MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR,
            abi.encodeWithSelector(ICurveLpConnector.rate.selector, MC.CURVE_LP_YNETH_YNLSDE_POOL),
            abi.encode(int256(1.5e18), block.timestamp) // Mock rate of 1.5 ETH per LP token
        );
        // Test vault accounting
        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);

        vault.processAccounting();

        // uint256 expectedBaseValue = (strategyBalance * rate) / 1e18;
        // assertEq(vault.totalAssets(), expectedBaseValue, "Vault should account strategy value correctly");
    }

    function test_strategyRateReverts_whenStale() public {
        vm.warp(block.timestamp + 10 hours);
        // Mock stale rate (> 5 hours old)
        vm.mockCall(
            MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR,
            abi.encodeWithSelector(ICurveLpConnector.rate.selector, MC.CURVE_LP_YNETH_YNLSDE_POOL),
            abi.encode(int256(1.5e18), block.timestamp - 6 hours)
        );

        vm.expectRevert("Rate is stale");
        vault.processAccounting();
    }
}
