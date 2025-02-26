// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {ICurveLpConnector} from "src/interface/ICurveLpConnector.sol";
import {ICurvePool} from "test/interface/external/curve/ICurvePool.sol";

contract TokenizedLPStrategyUnitTest is Test, MainnetActors {
    IERC20 public strategy;
    Vault public vault;
    ICurvePool public pool;
    ICurveLpConnector public connector;
    uint256 public constant INITIAL_BALANCE = 101 ether;

    address public constant ASSET_A = MC.YNETH;
    address public constant ASSET_B = MC.YNLSDE;

    address public alice = address(0xa11c3);

    function setUp() public {
        vault = Vault(payable(MC.YNETHX));
        connector = ICurveLpConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);

        assertEq(address(connector.STRATEGY()), MC.CURVE_LP_YNETH_YNLSDE_STRATEGY);
        assertEq(address(connector.ASSET_A()), ASSET_A);
        assertEq(address(connector.ASSET_B()), ASSET_B);

        strategy = IERC20(payable(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY));

        pool = ICurvePool(payable(MC.CURVE_LP_YNETH_YNLSDE_POOL));

        connector = ICurveLpConnector(payable(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR));

        vm.label(address(pool), "pool");
        vm.label(address(strategy), "strategy");
        vm.label(address(vault), "vault");

        // grant PROCESSOR_ROLE to this contract for processor
        vm.startPrank(ADMIN);
        vault.grantRole(vault.PROCESSOR_ROLE(), address(this));
        vm.stopPrank();

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_processAccounting() public {
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);
        assertEq(strategy.balanceOf(address(vault)), strategyBalance, "Strategy balance should be 1");

        vault.processAccounting();
        (int256 rate,) = connector.rate();
        uint256 expectedBaseValue = (strategyBalance * uint256(rate)) / 1e18;
        assertEq(
            vault.totalAssets(), totalAssetsBefore + expectedBaseValue, "Vault should account strategy value correctly"
        );
    }

    function test_strategyRateReverts_whenNegative() public {
        vm.mockCall(
            address(connector),
            abi.encodeWithSelector(ICurveLpConnector.rate.selector),
            // solhint-disable-next-line not-rely-on-time
            abi.encode(int256(-1), block.timestamp)
        );

        uint256 strategyBalance = 1e18; // 1 strategy token
        deal(address(strategy), address(vault), strategyBalance);

        vm.expectRevert(Provider.RateIsNegative.selector);
        vault.processAccounting();
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = vault.buffer();

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(PROCESSOR);
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
            deal(MC.WETH, alice, assets);

            // Test the deposit function
            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), assets);
            uint256 depositedShares = vault.deposit(assets, alice);
            vm.stopPrank();

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
            uint256 maxWithdraw = vault.maxWithdraw(alice);
            assertGt(maxWithdraw, 0, "Max withdraw should be greater than 0");

            uint256 balanceBefore = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferBefore = IERC20(MC.WETH).balanceOf(vault.buffer());

            uint256 convertedShares = vault.convertToShares(maxWithdraw);

            // Test the withdraw function
            vm.startPrank(alice);
            uint256 withdrawnShares = vault.withdraw(maxWithdraw, alice, alice);
            vm.stopPrank();
            assertApproxEqRel(
                withdrawnShares, convertedShares, 2e15, "Withdrawn shares should equal the converted shares"
            );

            uint256 balanceAfter = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferAfter = IERC20(MC.WETH).balanceOf(vault.buffer());

            assertEq(balanceBefore, balanceAfter, "WETH balance should not change");
            assertEq(bufferAfter, bufferBefore - maxWithdraw, "Buffer balance should increase by buffer amount");
        }
    }

    // function test_connector_deposit(uint256 amountA) public {
    //     vm.assume(amountA > 100000000 && amountA < 100_000 ether);

    //     uint256 amountB = amountA;
    //     deal(ASSET_A, alice, amountA);
    //     deal(ASSET_B, alice, amountB);

    //     vm.startPrank(alice);
    //     IERC20(ASSET_A).approve(address(vault), amountA);
    //     IERC20(ASSET_B).approve(address(vault), amountB);
    //     vault.depositAsset(ASSET_A, amountA, alice);
    //     vault.depositAsset(ASSET_B, amountB, alice);
    //     vm.stopPrank();

    //     vault.processAccounting();

    //     assertEq(IERC20(ASSET_A).balanceOf(address(vault)), amountA, "Asset A balance should match deposit");
    //     assertEq(IERC20(ASSET_B).balanceOf(address(vault)), amountB, "Asset B balance should match deposit");

    //     uint256 initialTotalAssets = vault.totalAssets();
    //     assertEq(strategy.balanceOf(address(vault)), 0, "Strategy balance should be zero");

    //     uint256 shares = _processConnectorDeposit(vault, address(connector), ASSET_A, ASSET_B, amountA, amountB, 0);

    //     vault.processAccounting();

    //     assertEq(strategy.balanceOf(address(vault)), shares, "Strategy balance should match shares");
    //     assertEq(IERC20(ASSET_A).balanceOf(address(vault)), 0, "Asset A balance should be zero");
    //     assertEq(IERC20(ASSET_B).balanceOf(address(vault)), 0, "Asset B balance should be zero");

    //     uint256 assetARate = IProvider(vault.provider()).getRate(ASSET_A);
    //     uint256 amountAInBase = amountA * assetARate / 1e18;

    //     uint256 assetBRate = IProvider(vault.provider()).getRate(ASSET_B);
    //     uint256 amountBInBase = amountB * assetBRate / 1e18;

    //     uint256 strategyRate = IProvider(vault.provider()).getRate(address(strategy));
    //     uint256 sharesInBase = shares * strategyRate / 1e18;

    //     assertApproxEqRel(sharesInBase, amountAInBase + amountBInBase, 1e12, "Shares should match expected");

    //     assertApproxEqRel(vault.totalAssets(), initialTotalAssets, 1e12, "Total assets should not change");
    // }

    // function test_connector_deposit_withdraw(uint256 amountA) public {
    //     vm.assume(amountA > 100000000 && amountA < 100_000 ether);

    //     uint256 amountB = amountA;
    //     deal(ASSET_A, alice, amountA);
    //     deal(ASSET_B, alice, amountB);

    //     vm.startPrank(alice);
    //     IERC20(ASSET_A).approve(address(vault), amountA);
    //     IERC20(ASSET_B).approve(address(vault), amountB);
    //     vault.depositAsset(ASSET_A, amountA, alice);
    //     vault.depositAsset(ASSET_B, amountB, alice);
    //     vm.stopPrank();

    //     vault.processAccounting();

    //     assertEq(IERC20(ASSET_A).balanceOf(address(vault)), amountA, "Asset A balance should match deposit");
    //     assertEq(IERC20(ASSET_B).balanceOf(address(vault)), amountB, "Asset B balance should match deposit");

    //     uint256 initialTotalAssets = vault.totalAssets();
    //     assertEq(strategy.balanceOf(address(vault)), 0, "Strategy balance should be zero");

    //     // ============= DEPOSIT #1 =============

    //     uint256 shares = _processConnectorDeposit(vault, address(connector), ASSET_A, ASSET_B, amountA, amountB, 0);

    //     vault.processAccounting();

    //     assertEq(strategy.balanceOf(address(vault)), shares, "Strategy balance should match shares");

    //     assertEq(IERC20(ASSET_A).balanceOf(address(vault)), 0, "Asset A balance should be zero");
    //     assertEq(IERC20(ASSET_B).balanceOf(address(vault)), 0, "Asset B balance should be zero");
    //     assertApproxEqRel(
    //         vault.totalAssets(), initialTotalAssets, 1e12, "Total assets should not change after first deposit"
    //     );

    //     // ============= WITHDRAW #1 =============

    //     // Withdraw all shares with minimum amounts of 1000 for each asset to protect against slippage
    //     _processConnectorWithdraw(vault, address(connector), address(strategy), shares, 1000, 1000);

    //     vault.processAccounting();

    //     assertEq(strategy.balanceOf(address(vault)), 0, "Strategy balance should be zero");

    //     // IMPORTANT: this may not be true due to slippage if the pool is not balanced
    //     // This test may break in the future in which case asset-ratio based withdrawals should be used
    //     // The higher tolerance is due to the fact that the pool may not balanced
    //     assertApproxEqRel(
    //         IERC20(ASSET_B).balanceOf(address(vault)),
    //         amountB,
    //         1e16,
    //         "Asset B balance should be roughly equal to amountA"
    //     );
    //     assertApproxEqRel(
    //         IERC20(ASSET_A).balanceOf(address(vault)),
    //         amountA,
    //         1e16,
    //         "Asset A balance should be roughly equal to amountA"
    //     );

    //     // TOTAL ASSETS must stay roughly the same after withdrawals
    //     assertApproxEqRel(
    //         vault.totalAssets(), initialTotalAssets, 1e12, "Total assets should not change after first withdraw"
    //     );

    //     // ============= DEPOSIT #2 =============

    //     amountA = IERC20(ASSET_A).balanceOf(address(vault));
    //     amountB = IERC20(ASSET_B).balanceOf(address(vault));

    //     uint256 shares2 = _processConnectorDeposit(vault, address(connector), ASSET_A, ASSET_B, amountA, amountB, 0);

    //     vault.processAccounting();

    //     assertApproxEqRel(shares2, shares, 1e12, "Second shares should match shares");

    //     assertEq(strategy.balanceOf(address(vault)), shares2, "Strategy balance should match shares");

    //     assertEq(IERC20(ASSET_A).balanceOf(address(vault)), 0, "Asset A balance should be zero");
    //     assertEq(IERC20(ASSET_B).balanceOf(address(vault)), 0, "Asset B balance should be zero");

    //     assertApproxEqRel(shares2, shares, 1e12, "Second shares should match shares");
    //     assertApproxEqRel(
    //         vault.totalAssets(), initialTotalAssets, 1e12, "Total assets should not change after second deposit"
    //     );

    //     // ============= WITHDRAW #2 =============

    //     _processConnectorWithdraw(vault, address(connector), address(strategy), shares2, 500, 500);

    //     vault.processAccounting();

    //     assertEq(strategy.balanceOf(address(vault)), 0, "Strategy balance should be zero");

    //     // IMPORTANT: this may not be true due to slippage if the pool is not balanced
    //     // This test may break in the future in which case asset-ratio based withdrawals should be used
    //     assertApproxEqRel(
    //         IERC20(ASSET_B).balanceOf(address(vault)),
    //         amountB,
    //         1e16,
    //         "Asset B balance should be roughly equal to amountA"
    //     );
    //     assertApproxEqRel(
    //         IERC20(ASSET_A).balanceOf(address(vault)),
    //         amountA,
    //         1e16,
    //         "Asset A balance should be roughly equal to amountA"
    //     );
    //     assertApproxEqRel(
    //         vault.totalAssets(), initialTotalAssets, 1e12, "Total assets should not change after second withdraw"
    //     );
    // }

    function _processConnectorDeposit(
        IVault vault_,
        address connectorAddress,
        address assetA,
        address assetB,
        uint256 amountA,
        uint256 amountB,
        uint256 minOut
    ) internal returns (uint256 shares) {
        address[] memory targets = new address[](3);
        targets[0] = assetA;
        targets[1] = assetB;
        targets[2] = connectorAddress;

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", connectorAddress, amountA);
        data[1] = abi.encodeWithSignature("approve(address,uint256)", connectorAddress, amountB);
        data[2] = abi.encodeWithSignature("deposit(uint256,uint256,uint256)", amountA, amountB, minOut);

        bytes[] memory returnData = vault_.processor(targets, values, data);

        shares = abi.decode(returnData[2], (uint256));
    }

    function _processConnectorWithdraw(
        IVault vault_,
        address connectorAddress,
        address strategyAddress,
        uint256 amount,
        uint256 minAmountA,
        uint256 minAmountB
    ) internal returns (uint256[2] memory) {
        address[] memory targets = new address[](2);
        targets[0] = strategyAddress;
        targets[1] = connectorAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", connectorAddress, amount);
        data[1] = abi.encodeWithSignature("withdraw(uint256,uint256,uint256)", amount, minAmountA, minAmountB);

        bytes[] memory returnData = vault_.processor(targets, values, data);

        return abi.decode(returnData[1], (uint256[2]));
    }
}
