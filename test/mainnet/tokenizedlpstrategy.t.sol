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
import {ICurvePool} from "test/interface/external/curve/ICurvePool.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";

contract TokenizedLPStrategyUnitTest is Test, MainnetActors, Etches, ConnectorRules, BaseRules {
    MockTokenizedStrategy public strategy;
    Vault public vault;
    ICurvePool public pool;
    MockConnector public connector;
    uint256 public constant INITIAL_BALANCE = 101 ether;
    uint256 public constant MOCK_RATE = 1.2 ether;

    address public constant ASSET_A = MC.YNETH;
    address public constant ASSET_B = MC.YNLSDE;

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

        mockConnector(address(vault), address(strategy), ASSET_A, ASSET_B);

        vm.label(address(pool), "pool");
        vm.label(address(strategy), "strategy");
        vm.label(address(vault), "vault");

        configureVault();
    }

    function configureVault() public {
        vm.startPrank(ADMIN);
        vault.addAsset(address(strategy), false);
        vault.grantRole(vault.PROCESSOR_ROLE(), address(this));
        setApprovalRule(vault, ASSET_A, address(connector));
        setApprovalRule(vault, ASSET_B, address(connector));
        setConnectorDepositRule(vault, address(connector));
        setConnectorWithdrawRule(vault, address(connector));
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

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function totalSupplyInvariant(uint256 supply) public view {
        uint256 finalVaultTotalSupply = vault.totalSupply();
        assertApproxEqRel(
            supply, finalVaultTotalSupply, 1e15, "Vault totalSupply should be original totalSupply plus additional"
        );
    }

    function totalAssetsInvariant(uint256 assets) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertApproxEqRel(
            assets, finalVaultTotalAssets, 1e15, "Vault totalAssets should be original totalAssets plus additional"
        );
    }

    function test_deposit_allocateToBuffer_withdraw(uint256 assets, uint256 bufferAmount) public {
        vm.assume(assets > 10000 && assets < 100_000_000 ether);
        vm.assume(bufferAmount > 10000 && bufferAmount < assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Decimals should be 18");

        // Test the asset function
        assertEq(vault.asset(), MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        assertGt(vault.totalAssets(), 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        assertApproxEqRel(
            vault.convertToAssets(shares), assets, 1e15, "Converted assets should equal the original assets"
        );

        uint256 previewedShares = vault.previewDeposit(assets);
        assertApproxEqRel(previewedShares, shares, 1e15, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqRel(previewedAssets, assets, 1e15, "Previewed assets should equal the original assets");

        {
            deal(MC.WETH, address(this), assets);
            IERC20(MC.WETH).approve(address(vault), assets);

            // Test the deposit function
            uint256 depositedShares = vault.deposit(assets, address(this));
            assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");
        }

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);

        {
            uint256 balanceBefore = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferBefore = IERC20(MC.WETH).balanceOf(vault.buffer());

            // allocate to buffer
            allocateToBuffer(bufferAmount);

            uint256 balanceAfter = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferAfter = IERC20(MC.WETH).balanceOf(vault.buffer());
            assertEq(balanceBefore - balanceAfter, bufferAmount, "WETH balance should decrease by buffer amount");
            assertEq(bufferAfter - bufferBefore, bufferAmount, "Buffer balance should increase by buffer amount");
        }

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);

        {
            uint256 maxWithdraw = vault.maxWithdraw(address(this));
            assertGt(maxWithdraw, 0, "Max withdraw should be greater than 0");

            uint256 balanceBefore = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferBefore = IERC20(MC.WETH).balanceOf(vault.buffer());

            uint256 convertedShares = vault.convertToShares(maxWithdraw);

            // Test the withdraw function
            uint256 withdrawnShares = vault.withdraw(maxWithdraw, address(this), address(this));
            assertApproxEqRel(
                withdrawnShares, convertedShares, 1e15, "Withdrawn shares should equal the converted shares"
            );

            uint256 balanceAfter = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferAfter = IERC20(MC.WETH).balanceOf(vault.buffer());

            assertEq(balanceBefore, balanceAfter, "WETH balance should not change");
            assertEq(bufferAfter, bufferBefore - maxWithdraw, "Buffer balance should increase by buffer amount");
        }
    }

    function test_connector_deposit(uint256 amountA, uint256 amountB) public {
        vm.assume(amountA > 1000 && amountA < 1000 ether);
        vm.assume(amountB > 1000 && amountB < 1000 ether);

        deal(ASSET_A, address(vault), amountA);
        deal(ASSET_B, address(vault), amountB);

        assertEq(strategy.balanceOf(address(vault)), 0, "Strategy balance should be zero");

        uint256 shares = processConnectorDeposit(vault, address(connector), ASSET_A, ASSET_B, amountA, amountB, 0);

        assertEq(strategy.balanceOf(address(vault)), shares, "Strategy balance should match shares");
    }
}
