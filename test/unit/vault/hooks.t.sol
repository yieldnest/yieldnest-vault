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

        uint256 yieldEarned = yieldAmount1;

        uint256 performanceFee = IHooks(address(vault.hooks())).performanceFee();
        uint256 performanceFeeAmount = (yieldEarned * performanceFee) / 1 ether;
        uint256 totalBaseAssets = vault.computeTotalAssets();
        (uint256 performanceFeeShares,) =
            convertToShares(performanceFeeAmount, vault.totalSupply(), totalBaseAssets, Math.Rounding.Floor);

        vault.processAccounting();

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        // assertEqThreshold(totalAssets, depositAmount1 + depositAmount2 + yieldEarned, 5000, "totalAssets should match expected");
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

    function test_chargePerformanceFee_WithoutYield(uint256 wethAmount) public {
        // Bound inputs to reasonable ranges
        wethAmount = bound(wethAmount, 1 ether, 10_000 ether);

        // Initial deposit of WETH through deposit function
        vm.startPrank(alice);
        uint256 shares = vault.deposit(wethAmount, alice);
        uint256 expectedTotalAssets = wethAmount;
        uint256 expectedTotalSupply = shares;
        vm.stopPrank();

        address hooks = address(vault.hooks());
        uint256 performanceFee = IHooks(hooks).performanceFee();
        uint256 totalBaseAssets = vault.computeTotalAssets();
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

    function test_chargePerformanceFee_NotCalledByVault() public {
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

    function convertToShares(uint256 baseAssets, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
        return (shares, baseAssets);
    }
}
