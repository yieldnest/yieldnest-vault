// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Hooks} from "src/Hooks.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "src/Common.sol";
import {console} from "lib/forge-std/src/console.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HooksUnitTest is Test, MainnetActors, Etches, AssertUtils {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;

    WETH9 public weth;
    MockSTETH public steth;
    Hooks public hooks;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();
        hooks = Hooks(address(vault.hooks()));

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MC.STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_AfterProcessAccounting_Invariants(
        uint256 totalAssetsBefore,
        uint256 totalAssetsAfter,
        uint256 performanceFee
    ) public {
        totalAssetsBefore = bound(totalAssetsBefore, 1 ether, 1_000_000_000 ether);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 1 ether, 1_000_000_001 ether);
        performanceFee = bound(performanceFee, 0.01 ether, 1 ether);

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(performanceFee);
        vm.stopPrank();

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 18);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        deal((MC.WETH), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.WETH).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.WETH).transfer(address(vault), donationAmount);
        vm.stopPrank();

        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        uint256 feesAccrued = (donationAmount * hooks.performanceFee()) / 1 ether;

        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        if (feesAccrued > 0) {
            assertGt(
                vaultTotalSupplyAfter,
                vaultTotalSupplyBefore,
                "vault's total supply should increase due to fee shares minted"
            );
            uint256 performanceFeeShares = vaultTotalSupplyAfter - vaultTotalSupplyBefore;
            assertEq(
                performanceFeeShares,
                vault.balanceOf(vault.hooks().performanceFeeRecipient()),
                "performance fee shares should be equal to performance fee recipient's balance"
            );
            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeShares),
                feesAccrued,
                1e12,
                "performance fee shares should be equal to performance fee amount"
            );
        } else {
            assertEq(
                vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee"
            );
        }
        assertGe(
            vaultExchangeRateAfter,
            vaultExchangeRateBefore,
            "vault's exchange rate should always increase due to donation"
        );
    }

    function test_AfterProcessingAccountWithNoPerformanceFee(uint256 totalAssetsBefore, uint256 totalAssetsAfter)
        public
    {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0);
        vm.stopPrank();

        totalAssetsBefore = bound(totalAssetsBefore, 1 ether, 1_000_000_000 ether);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 1 ether, 1_000_000_002 ether);

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 18);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        deal((MC.WETH), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.WETH).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.WETH).transfer(address(vault), donationAmount);
        vm.stopPrank();

        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        assertEq(vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee");
        assertGt(
            vaultExchangeRateAfter,
            vaultExchangeRateBefore,
            "vault's exchange rate should always increase due to donation"
        );

        vm.stopPrank();
    }

    function test_AfterProcessAccounting_MultipleDeposits(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint256 yieldAmount1,
        uint256 performanceFee
    ) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        depositAmount1 = bound(depositAmount1, 1 ether, 10_000 ether);
        depositAmount2 = bound(depositAmount2, 1 ether, 10_000 ether);
        yieldAmount1 = bound(yieldAmount1, 1 ether, 10_000 ether);
        performanceFee = bound(performanceFee, 0.01 ether, 1 ether);

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(performanceFee);
        vm.stopPrank();

        deal((MC.WETH), user1, depositAmount1);
        deal((MC.WETH), user2, depositAmount2 + yieldAmount1);

        vm.startPrank(user1);
        IERC20(MC.WETH).approve(address(vault), depositAmount1);
        uint256 shares1 = vault.deposit(depositAmount1, user1);
        vault.processAccounting();
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(MC.WETH).approve(address(vault), depositAmount2);
        uint256 shares2 = vault.deposit(depositAmount2, user2);
        vault.processAccounting();
        IERC20(MC.WETH).transfer(address(vault), yieldAmount1);
        vm.stopPrank();

        uint256 performanceFeeShares;
        uint256 performanceFeeAmount;
        {
            performanceFeeAmount = (yieldAmount1 * performanceFee) / 1 ether;
            uint256 sharesOfFeeRecipientBefore = vault.balanceOf(vault.hooks().performanceFeeRecipient());
            vault.processAccounting();
            uint256 sharesOfFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
            performanceFeeShares = sharesOfFeeRecipientAfter - sharesOfFeeRecipientBefore;
        }

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertApproxEqAbs(
            vault.convertToAssets(performanceFeeShares),
            performanceFeeAmount,
            1e12,
            "performance fee shares should be equal to performance fee amount"
        );
        assertEqThreshold(
            totalAssets, depositAmount1 + depositAmount2 + yieldAmount1, 5000, "totalAssets should match expected"
        );
        assertEqThreshold(
            totalSupply, shares1 + shares2 + performanceFeeShares, 5000, "totalSupply should match expected"
        );

        assertEqThreshold(
            vault.balanceOf(FEE_MANAGER),
            performanceFeeShares,
            5000,
            "FEE_MANAGER should have the performance fee shares"
        );
    }

    function test_AfterProcessAccounting_WithoutYield(uint256 wethAmount) public {
        // Bound inputs to reasonable ranges
        wethAmount = bound(wethAmount, 1 ether, 10_000 ether);

        // Initial deposit of WETH through deposit function
        vm.startPrank(alice);
        uint256 shares = vault.deposit(wethAmount, alice);
        uint256 expectedTotalAssets = wethAmount;
        uint256 expectedTotalSupply = shares;
        vm.stopPrank();

        uint256 totalSupplyBeforeProcessing = vault.totalSupply();

        vault.processAccounting();

        uint256 totalSupplyAfterProcessing = vault.totalSupply();

        assertEq(
            totalSupplyBeforeProcessing, totalSupplyAfterProcessing, "totalSupply should stay the same due to no yield"
        );

        uint256 totalAssets = vault.totalAssets();

        assertEq(vault.balanceOf(FEE_MANAGER), 0, "FEE_MANAGER should have no shares");
        assertEqThreshold(totalAssets, expectedTotalAssets, 5000, "totalAssets should match expected");
        assertEqThreshold(totalSupplyBeforeProcessing, expectedTotalSupply, 5000, "totalSupply should match expected");
    }

    function test_AfterProcessAccounting_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterProcessAccounting(1 ether, 1 ether, 1 ether);
        vm.stopPrank();
    }

    function test_setPerformanceFeeRecipient() public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");
        vm.startPrank(ADMIN);
        hooks.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
        assertEq(hooks.performanceFeeRecipient(), newPerformanceFeeRecipient);
    }

    function test_setPerformanceFeeRecipient_notAdmin() public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        hooks.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function test_setPerformanceFeeRecipient_invalidRecipient() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IHooks.InvalidPerformanceFeeRecipient.selector));
        hooks.setPerformanceFeeRecipient(address(0));
    }

    function test_setPerformanceFee() public {
        uint256 newPerformanceFee = 1e16;
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(newPerformanceFee);
        assertEq(hooks.performanceFee(), newPerformanceFee);
    }

    function test_setPerformanceFee_notAdmin() public {
        uint256 newPerformanceFee = 1e16;
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        hooks.setPerformanceFee(newPerformanceFee);
    }

    function test_setPerformanceFee_invalidFee() public {
        uint256 newPerformanceFee = 1e19;
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IHooks.InvalidPerformanceFee.selector));
        hooks.setPerformanceFee(newPerformanceFee);
    }

    function test_setHooks_revertsIfInvalidHooks() public {
        SetupVault setupVault = new SetupVault();
        (Vault dummyVault,) = setupVault.setup();
        address invalidHooks = address(new Hooks(address(dummyVault)));
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidHooks.selector));
        vault.setHooks(invalidHooks);
    }
}
