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
import {FeeModule} from "src/FeeModule.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "src/Common.sol";
import {console} from "lib/forge-std/src/console.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IFeeModule} from "src/interface/IFeeModule.sol";

contract FeeModuleUnitTest is Test, MainnetActors, Etches, AssertUtils {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;

    WETH9 public weth;
    MockSTETH public steth;
    FeeModule public feeModule;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();
        feeModule = FeeModule(vault.feeModule());

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

    function test_Updates_MaximumAccountedExchangeRate_After_ChargePerformanceFee(uint256 wethAmount) public {
        // Bound inputs to reasonable ranges
        wethAmount = bound(wethAmount, 1 ether, 10_000 ether);

        uint256 maximumAccountedExchangeRateBefore = FeeModule(vault.feeModule()).maximumAccountedExchangeRate();

        // Initial deposit of WETH through deposit function
        vm.startPrank(alice);
        uint256 shares = vault.deposit(wethAmount, alice);
        uint256 expectedTotalAssets = wethAmount;
        uint256 expectedTotalSupply = shares;
        vm.stopPrank();

        vault.processAccounting();

        // Direct transfer of WETH
        deal(alice, wethAmount);
        (bool success,) = MC.WETH.call{value: wethAmount}("");
        assertTrue(success, "WETH transfer failed");
        vm.prank(alice);
        IERC20(MC.WETH).transfer(address(vault), wethAmount);
        expectedTotalAssets += wethAmount;
        uint256 yieldEarned = wethAmount;

        address feeModule = vault.feeModule();
        uint256 performanceFee = FeeModule(feeModule).performanceFee();
        uint256 performanceFeeAmount = (yieldEarned * performanceFee) / 1 ether;
        uint256 totalBaseAssets = vault.computeTotalAssets();
        (uint256 performanceFeeShares,) =
            convertToShares(performanceFeeAmount, vault.totalSupply(), totalBaseAssets, Math.Rounding.Floor);
        uint256 feeManagerSharesBeforeProcessing = vault.balanceOf(FEE_MANAGER);

        vault.processAccounting();

        uint256 maximumAccountedExchangeRateAfter = FeeModule(vault.feeModule()).maximumAccountedExchangeRate();

        assertGt(
            maximumAccountedExchangeRateAfter,
            maximumAccountedExchangeRateBefore,
            "maximumAccountedExchangeRate should increase"
        );
        assertEq(
            maximumAccountedExchangeRateAfter,
            vault.convertToAssets(1 ether),
            "maximumAccountedExchangeRate should be equal to the exchange rate of 1 ether"
        );

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        assertEqThreshold(
            vault.balanceOf(FEE_MANAGER) - feeManagerSharesBeforeProcessing,
            performanceFeeShares,
            5000,
            "FEE_MANAGER should have the performance fee shares"
        );
        assertEqThreshold(totalAssets, expectedTotalAssets, 5000, "totalAssets should match expected");
        assertEqThreshold(
            totalSupply, expectedTotalSupply + performanceFeeShares, 5000, "totalSupply should match expected"
        );
    }

    function test_ChargePerformanceFee_MultipleDeposits(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint256 yieldAmount1
    ) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        depositAmount1 = bound(depositAmount1, 1 ether, 10_000 ether);
        depositAmount2 = bound(depositAmount2, 1 ether, 10_000 ether);
        yieldAmount1 = bound(yieldAmount1, 1 ether, 10_000 ether);

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

        uint256 maximumAccountedExchangeRateBefore = FeeModule(vault.feeModule()).maximumAccountedExchangeRate();
        uint256 yieldEarned = yieldAmount1;

        address feeModule = vault.feeModule();
        uint256 performanceFee = FeeModule(feeModule).performanceFee();
        uint256 performanceFeeAmount = (yieldEarned * performanceFee) / 1 ether;
        uint256 totalBaseAssets = vault.computeTotalAssets();
        (uint256 performanceFeeShares,) =
            convertToShares(performanceFeeAmount, vault.totalSupply(), totalBaseAssets, Math.Rounding.Floor);

        vault.processAccounting();

        uint256 maximumAccountedExchangeRateAfter = FeeModule(vault.feeModule()).maximumAccountedExchangeRate();
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        // assertEqThreshold(totalAssets, depositAmount1 + depositAmount2 + yieldEarned, 5000, "totalAssets should match expected");
        assertEqThreshold(
            totalSupply, shares1 + shares2 + performanceFeeShares, 5000, "totalSupply should match expected"
        );

        assertGt(
            maximumAccountedExchangeRateAfter,
            maximumAccountedExchangeRateBefore,
            "maximumAccountedExchangeRate should increase"
        );
        assertEq(
            maximumAccountedExchangeRateAfter,
            vault.convertToAssets(1 ether),
            "maximumAccountedExchangeRate should be equal to the exchange rate of 1 ether"
        );

        assertEqThreshold(
            vault.balanceOf(FEE_MANAGER),
            performanceFeeShares,
            5000,
            "FEE_MANAGER should have the performance fee shares"
        );
    }

    function test_chargePerformanceFee_WithoutYield(uint256 wethAmount) public {
        // Bound inputs to reasonable ranges
        wethAmount = bound(wethAmount, 1 ether, 10_000 ether);

        uint256 maximumAccountedExchangeRateBefore = FeeModule(vault.feeModule()).maximumAccountedExchangeRate();

        // Initial deposit of WETH through deposit function
        vm.startPrank(alice);
        uint256 shares = vault.deposit(wethAmount, alice);
        uint256 expectedTotalAssets = wethAmount;
        uint256 expectedTotalSupply = shares;
        vm.stopPrank();

        address feeModule = vault.feeModule();
        uint256 performanceFee = FeeModule(feeModule).performanceFee();
        uint256 totalBaseAssets = vault.computeTotalAssets();
        uint256 totalSupplyBeforeProcessing = vault.totalSupply();

        vault.processAccounting();

        uint256 totalSupplyAfterProcessing = vault.totalSupply();

        assertEq(
            totalSupplyBeforeProcessing, totalSupplyAfterProcessing, "totalSupply should stay the same due to no yield"
        );

        uint256 maximumAccountedExchangeRateAfter = FeeModule(vault.feeModule()).maximumAccountedExchangeRate();

        assertEq(
            maximumAccountedExchangeRateAfter,
            maximumAccountedExchangeRateBefore,
            "maximumAccountedExchangeRate should stay the same due to no yield"
        );
        assertEq(maximumAccountedExchangeRateAfter, 1 ether, "maximumAccountedExchangeRate should be equal to 1 ether");

        uint256 totalAssets = vault.totalAssets();

        assertEq(vault.balanceOf(FEE_MANAGER), 0, "FEE_MANAGER should have no shares");
        assertEqThreshold(totalAssets, expectedTotalAssets, 5000, "totalAssets should match expected");
        assertEqThreshold(totalSupplyBeforeProcessing, expectedTotalSupply, 5000, "totalSupply should match expected");
    }

    function test_chargePerformanceFee_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFeeModule.CallerNotVault.selector));
        feeModule.chargePerformanceFee();
        vm.stopPrank();
    }

    function test_setPerformanceFeeRecipient() public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");
        vm.startPrank(ADMIN);
        feeModule.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
        assertEq(feeModule.performanceFeeRecipient(), newPerformanceFeeRecipient);
    }

    function test_setPerformanceFeeRecipient_notAdmin() public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        feeModule.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function test_setPerformanceFee() public {
        uint256 newPerformanceFee = 1e16;
        vm.startPrank(ADMIN);
        feeModule.setPerformanceFee(newPerformanceFee);
        assertEq(feeModule.performanceFee(), newPerformanceFee);
    }

    function test_setPerformanceFee_notAdmin() public {
        uint256 newPerformanceFee = 1e16;
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        feeModule.setPerformanceFee(newPerformanceFee);
    }

    function test_setPerformanceFee_invalidFee() public {
        uint256 newPerformanceFee = 1e19;
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IFeeModule.InvalidPerformanceFee.selector));
        feeModule.setPerformanceFee(newPerformanceFee);
    }

    function convertToShares(uint256 baseAssets, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
        return (shares, baseAssets);
    }
}
