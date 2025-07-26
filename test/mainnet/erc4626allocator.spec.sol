// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ERC4626Allocator} from "src/buffer/ERC4626Allocator.sol";
import {IERC4626} from "src/Common.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {IERC20} from "src/Common.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

// Mainnet addresses
address constant MORPHO_MEV_CAPITAL_WETH = 0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8;
address constant STEAKHOUSE_ETH_VAULT = 0xBEEf050ecd6a16c4e7bfFbB52Ebba7846C4b8cD4;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant ADMIN = address(0xABCD); // test admin

contract ERC4626Allocator_Mainnet_Integration is Test {
    ERC4626Allocator allocator;
    MockProvider provider;
    address public user = address(0x1234);

    function setUp() public {
        // Deploy ERC4626Allocator logic contract
        ERC4626Allocator logic = new ERC4626Allocator();

        // Deploy TransparentUpgradeableProxy without initializer
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(logic),
            ADMIN, // proxy admin
            ""
        );

        // Call initialize separately with labeled params
        ERC4626Allocator(payable(address(proxy))).initialize(
            ADMIN, // admin
            "Test Allocator", // name
            "ALLOC", // symbol
            18, // decimals
            true, // countNativeAsset_
            false, // alwaysComputeTotalAssets_
            0 // defaultAssetIndex_
        );

        allocator = ERC4626Allocator(payable(address(proxy)));

        // Deploy and set up MockProvider
        provider = new MockProvider();

        // Add the vaults to the MockProvider as ERC4626
        provider.addERC4626(MORPHO_MEV_CAPITAL_WETH);
        provider.addERC4626(STEAKHOUSE_ETH_VAULT);

        // Set the provider in the allocator
        vm.startPrank(ADMIN);
        allocator.grantRole(allocator.VAULT_MANAGER_ROLE(), ADMIN);
        allocator.grantRole(allocator.ASSET_MANAGER_ROLE(), ADMIN);
        allocator.grantRole(allocator.PROCESSOR_ROLE(), ADMIN);
        allocator.grantRole(allocator.PAUSER_ROLE(), ADMIN);
        allocator.grantRole(allocator.UNPAUSER_ROLE(), ADMIN);
        allocator.grantRole(allocator.PROVIDER_MANAGER_ROLE(), ADMIN);
        allocator.grantRole(allocator.PROCESSOR_MANAGER_ROLE(), ADMIN);
        allocator.grantRole(allocator.PROCESSOR_ROLE(), ADMIN);

        // Set the provider address
        allocator.setProvider(address(provider));

        // Add WETH as asset
        allocator.addAsset(WETH, true);

        // Add the two vaults as assets (required for setVaults)
        allocator.addAsset(MORPHO_MEV_CAPITAL_WETH, true);
        allocator.addAsset(STEAKHOUSE_ETH_VAULT, true);

        // Set vaults: Morpho and Steakhouse
        address[] memory vaults = new address[](2);
        vaults[0] = MORPHO_MEV_CAPITAL_WETH;
        vaults[1] = STEAKHOUSE_ETH_VAULT;
        allocator.setVaults(vaults);

        allocator.unpause();

        vm.stopPrank();

        vm.startPrank(ADMIN);
        {
            // Add deposit rules for all vaults in a loop
            for (uint256 i = 0; i < vaults.length; i++) {
                SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(vaults[i], address(allocator));
                allocator.setProcessorRule(vaults[i], depositRule.funcSig, depositRule.rule);
            }

            // Add a single approval rule for WETH for the entire set of vaults
            SafeRules.RuleParams memory approveRule = BaseRules.getApprovalRule(WETH, vaults);
            allocator.setProcessorRule(WETH, approveRule.funcSig, approveRule.rule);
        }
        vm.stopPrank();
    }

    function testDepositAndWithdraw_MorphoAndSteakhouse() public {
        // Use WETH as the asset for deposit
        uint256 depositAmount = 1 ether;

        // Deal WETH to user
        deal(WETH, user, 1_000_000 ether);

        // User approves allocator to spend WETH
        vm.startPrank(user);
        IERC20(WETH).approve(address(allocator), depositAmount);

        // Deposit into allocator
        allocator.deposit(depositAmount, user);

        // Check allocator's WETH balance increased
        uint256 allocatorWethBal = IERC20(WETH).balanceOf(address(allocator));
        assertEq(allocatorWethBal, depositAmount, "Allocator should hold deposited WETH");

        // Simulate allocation: deposit WETH into Morpho and Steakhouse vaults
        // For this test, we call ERC4626Allocator's processor to deposit into vaults
        // (Assume processor role is granted to ADMIN for test)
        vm.startPrank(ADMIN);

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory datas = new bytes[](4);

        // Approve Morpho vault to pull WETH
        datas[0] = abi.encodeWithSelector(IERC20.approve.selector, MORPHO_MEV_CAPITAL_WETH, depositAmount / 2);
        targets[0] = WETH;
        values[0] = 0;

        // Approve Steakhouse vault to pull WETH
        datas[1] = abi.encodeWithSelector(IERC20.approve.selector, STEAKHOUSE_ETH_VAULT, depositAmount / 2);
        targets[1] = WETH;
        values[1] = 0;

        // Deposit into Morpho vault
        datas[2] = abi.encodeWithSelector(IERC4626.deposit.selector, depositAmount / 2, address(allocator));
        targets[2] = MORPHO_MEV_CAPITAL_WETH;
        values[2] = 0;

        // Deposit into Steakhouse vault
        datas[3] = abi.encodeWithSelector(IERC4626.deposit.selector, depositAmount / 2, address(allocator));
        targets[3] = STEAKHOUSE_ETH_VAULT;
        values[3] = 0;

        // Call processor to approve and deposit into both vaults
        allocator.processor(targets, values, datas);

        // Allocator's WETH balance should now be 0
        assertEq(IERC20(WETH).balanceOf(address(allocator)), 0, "Allocator WETH should be 0 after allocation");

        // Allocator should have shares in both vaults
        uint256 morphoShares = IERC20(MORPHO_MEV_CAPITAL_WETH).balanceOf(address(allocator));
        uint256 steakhouseShares = IERC20(STEAKHOUSE_ETH_VAULT).balanceOf(address(allocator));
        assertGt(morphoShares, 0, "Allocator should have Morpho shares");
        assertGt(steakhouseShares, 0, "Allocator should have Steakhouse shares");

        vm.stopPrank();

        // User withdraws
        vm.startPrank(user);
        uint256 shares = allocator.balanceOf(user);

        uint256 withdrawAmount = depositAmount - 5 wei;
        allocator.withdraw(withdrawAmount, user, user);

        // User should have WETH back (minus any fees, slippage, etc)
        uint256 userWeth = IERC20(WETH).balanceOf(user);
        assertGt(userWeth, 0.99 ether, "User should get most WETH back");

        // Allocator's shares in vaults should decrease
        uint256 morphoSharesAfter = IERC20(MORPHO_MEV_CAPITAL_WETH).balanceOf(address(allocator));
        uint256 steakhouseSharesAfter = IERC20(STEAKHOUSE_ETH_VAULT).balanceOf(address(allocator));
        assertLt(morphoSharesAfter, morphoShares, "Morpho shares should decrease");
        assertLt(steakhouseSharesAfter, steakhouseShares, "Steakhouse shares should decrease");

        vm.stopPrank();
    }
}
