// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, Math, TimelockController} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract VaultBufferInvariantsTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    BufferStrategy public bufferStrategy;
    Provider public provider;

    string public constant VAULT_VERSION = "0.1.0";

    function setUp() public {
        (vault, bufferStrategy, provider) = BaseTest.deploy();
        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function allocateToBuffer(uint256 depositAmount) public returns (uint256 bufferShares) {
        // Allocate to buffer (MorphoGauntletUSDC vault)
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = MC.USDC;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(bufferStrategy), depositAmount));

            targets[1] = address(bufferStrategy);
            values[1] = 0;
            data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();
        
            bufferShares = abi.decode(returnData[1], (uint256));
        }
        vault.processAccounting();
    }

    function test_Vault_4626Invariants_depositBase_WithBufferAllocation(uint256 assets, uint256 bufferAmount) public {
        assets = bound(assets, 1, 1000_000 * 1e6);
        bufferAmount = bound(bufferAmount, 1, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Decimals should be 18");

        // Test the asset function
        assertEq(vault.asset(), MC.USDC, "Asset address should be WETH");


        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        uint256 previewedShares = vault.previewDeposit(assets);
        assertEqThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEqThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        {
            // Test the depositAsset function
            deal(MC.USDC, address(this), assets);
            IERC20(MC.USDC).approve(address(vault), assets);

            address receiver = address(this);
            uint256 depositedShares = vault.deposit(assets, receiver);
            assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");
        }

        vault.processAccounting();

        totalSupplyInvariant(initialSupply + shares);
        uint256 rate = IProvider(vault.provider()).getRate(vault.asset());
        uint256 baseAmount = Math.mulDiv(assets, rate, 10 ** ERC20(MC.USDC).decimals(), Math.Rounding.Floor);
        totalAssetsInvariant(initialAssets + baseAmount);

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        uint256 bufferShares;
        {
            // allocate to buffer
            uint256 balanceBefore = IERC20(MC.USDC).balanceOf(address(vault));
            uint256 bufferBefore = IERC20(MC.USDC).balanceOf(vault.buffer());

            bufferShares = allocateToBuffer(bufferAmount);

            uint256 balanceAfter = IERC20(MC.USDC).balanceOf(address(vault));
            uint256 bufferAfter = IERC20(MC.USDC).balanceOf(vault.buffer());
            assertEq(balanceBefore - balanceAfter, bufferAmount, "USDC balance should decrease by buffer amount");
            assertEq(bufferAfter - bufferBefore, 0, "Buffer balance should be allocated to usdc core vault");
        }

        assertGt(bufferShares, 0, "Buffer shares should be greater than 0");

        uint256 bufferRate = IProvider(vault.provider()).getRate(vault.buffer());
        uint256 bufferAssets = Math.mulDiv(bufferShares, bufferRate, 1e18, Math.Rounding.Floor);
        bufferAmount = Math.mulDiv(bufferAmount, bufferRate, 1e6, Math.Rounding.Floor);

        assertApproxEqRel(bufferAssets, bufferAmount, 1e13, "Buffer assets should equal buffer amount");

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariant(initialAssets - bufferAmount + bufferAssets);
    }

    function testDonationToBuffer_withoutBufferAllocation() public {
        uint256 assets = 1000_000 * 1e6;
        uint256 bufferAmount = 500_000 * 1e6;

        // Initial state
        uint256 initialSupply = vault.totalSupply();
        uint256 initialAssets = vault.totalAssets();

        // Make initial deposit
        deal(MC.USDC, address(this), assets);
        IERC20(MC.USDC).approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, address(this));
        uint256 rate = IProvider(vault.provider()).getRate(vault.asset());
        uint256 baseAmount = Math.mulDiv(assets, rate, 10 ** ERC20(vault.asset()).decimals(), Math.Rounding.Floor);

        // Process accounting
        vault.processAccounting();

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + baseAmount);

        // Donate directly to buffer
        deal(MC.USDC, address(this), bufferAmount);
        IERC20(MC.USDC).transfer(vault.buffer(), bufferAmount);
        uint256 baseBufferAmount = Math.mulDiv(bufferAmount, rate, 10 ** ERC20(bufferStrategy.asset()).decimals(), Math.Rounding.Floor);

        // Allocate to buffer
        allocateToBuffer(bufferAmount);

        vault.processAccounting();

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + baseAmount);
    }

    function test_allocateToBuffer_syncDeposit_off() public {
        vm.prank(DEPOSIT_MANAGER);
        bufferStrategy.setSyncDeposit(false);

        uint256 assets = 1000_000 * 1e6;
        uint256 bufferAmount = 500_000 * 1e6;

        // Make initial deposit
        deal(MC.USDC, address(this), assets);
        IERC20(MC.USDC).approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, address(this));

        // Process accounting
        vault.processAccounting();

        // Allocate to buffer
        allocateToBuffer(bufferAmount);

        assertEq(IERC20(MC.USDC).balanceOf(vault.buffer()), bufferAmount, "Buffer should have received USDC");
    }

    function test_withdrawFromBuffer_notSyncWithdraw() public {
        vm.prank(DEPOSIT_MANAGER);
        bufferStrategy.setSyncWithdraw(false);

        uint256 depositAmount =  100_000e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        // Approve and deposit USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        allocateToBuffer(depositAmount);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        vm.startPrank(alice);
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vault.withdraw(maxWithdraw, alice, alice);
        vm.stopPrank();

        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice should not receive USDC");
        assertEq(vault.balanceOf(alice), aliceSharesBefore, "Alice should have same shares before");
    }
}