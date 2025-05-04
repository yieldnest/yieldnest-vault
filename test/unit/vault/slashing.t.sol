/* solhint-disable one-contract-per-file, gas-custom-errors */
// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {IERC20} from "src/Common.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";

contract VaultSlashingUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;
    MockERC4626 public mockVault;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Create a mock ERC4626 vault with WETH as the underlying asset
        mockVault = new MockERC4626(ERC20(address(weth)), "Mock Vault", "mVault");

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        {
            // Add mockVault as an asset to the vault
            vm.prank(ASSET_MANAGER);
            vault.addAsset(address(mockVault), false);

            // Set METH rate to 1.2 ETH
            MockProvider(MC.PROVIDER).addERC4626(address(mockVault));
        }

        // Set up approval rule for WETH to mockVault
        vm.startPrank(PROCESSOR_MANAGER);

        // Create an allowlist with mockVault
        address[] memory allowList = new address[](2);
        allowList[0] = address(mockVault);
        allowList[1] = MC.BUFFER;

        // Set up approval rule for WETH
        SafeRules.RuleParams memory approvalRuleParams = BaseRules.getApprovalRule(address(weth), allowList);
        vault.setProcessorRule(approvalRuleParams.contractAddress, approvalRuleParams.funcSig, approvalRuleParams.rule);

        // Set up deposit rule for mockVault
        SafeRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(address(mockVault), address(vault));
        vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);

        vm.stopPrank();
    }

    function test_deposit_1000_WETH() public {
        // Define the deposit amount
        uint256 depositAmount = 1000 ether;

        // Perform the deposit as Alice
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Allocate the deposited WETH to the mock buffer strategy
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(mockVault), depositAmount, PROCESSOR);

        // Verify the allocation was successful
        assertEq(weth.balanceOf(address(vault)), 0, "Vault should have transferred all WETH to mock buffer");
        assertEq(
            IERC20(address(mockVault)).balanceOf(address(vault)),
            depositAmount,
            "Mock buffer should have received the deposit amount"
        );

        // Simulate a loss in the mock vault (slashing)
        uint256 slashFraction = 0.3 ether; // 30% loss

        // Store the total assets before slashing
        uint256 totalAssetsBeforeSlash = vault.totalAssets();

        // Use the slash function to simulate the loss
        mockVault.slash(slashFraction);

        // Get the balance of underlying assets in mockVault after slashing
        uint256 remainingAmount = IERC20(mockVault.asset()).balanceOf(address(mockVault));

        // Verify the slashing occurred
        uint256 vaultSharesValue = mockVault.convertToAssets(mockVault.balanceOf(address(vault)));
        assertEq(vaultSharesValue, remainingAmount, "Mock vault shares should be worth less after slashing");

        assertEq(
            vault.totalAssets(), totalAssetsBeforeSlash, "Total assets stay the same until processAccounting is called"
        );

        // Call processAccounting to update the vault's accounting
        vm.prank(PROCESSOR);
        vault.processAccounting();

        // Verify that total assets have been updated after processAccounting
        uint256 totalAssetsAfterAccounting = vault.totalAssets();

        assertLt(
            totalAssetsAfterAccounting,
            totalAssetsBeforeSlash,
            "Total assets should decrease after processAccounting due to slashing"
        );

        assertEq(
            totalAssetsAfterAccounting,
            remainingAmount,
            "Total assets should match the value of shares in mock vault after accounting"
        );
    }
}
