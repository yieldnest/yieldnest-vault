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
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {SetupBase6DecimalsVault} from "test/unit/vault/base6decimals/SetupBase6DecimalsVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BaseStrategy6DecimalsBaseDepositUnitTest is Test, MainnetActors, Etches {
// function test_Vault_withdrawUSDE_afterUSDCDeposit() public {
//     uint256 usdcDepositAmount = 1000e6; // USDC has 6 decimals
//     uint256 usdeDepositAmount = 1000e18; // USDE has 18 decimals

//     // Give Alice USDC
//     deal(MC.USDC, alice, usdcDepositAmount);

//     // Approve vault to spend Alice's USDC
//     vm.startPrank(alice);
//     IERC20(MC.USDC).approve(address(vault), type(uint256).max);

//     // Deposit USDC using depositAsset
//     uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
//     vm.stopPrank();

//     // Check that the vault received the USDC
//     assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

//     // Give Alice USDE
//     deal(MC.USDE, alice, usdeDepositAmount);

//     // Approve vault to spend Alice's USDE
//     vm.startPrank(alice);
//     IERC20(MC.USDE).approve(address(vault), type(uint256).max);

//     // Deposit USDE using depositAsset
//     uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
//     vm.stopPrank();

//     // Check that the vault received the USDE
//     assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

//     // Withdraw USDE using withdrawAsset
//     vm.startPrank(alice);
//     uint256 assetsWithdrawn = vault.withdrawAsset(MC.USDE, sharesMintedFromUSDE, alice, alice);
//     vm.stopPrank();

//     // Check that the vault sent back the USDE
//     assertEq(IERC20(MC.USDE).balanceOf(address(vault)), 0, "Vault did not send back USDE");

//     // Check that Alice's USDE balance increased
//     assertEq(
//         IERC20(MC.USDE).balanceOf(alice),
//         usdeDepositAmount,
//         "Alice's USDE balance did not increase correctly"
//     );

//     // Check that all shares from USDE deposit were burned
//     assertEq(vault.balanceOf(alice), sharesMintedFromUSDC, "Alice's shares from USDE were not burned correctly");

//     // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
//     assertEq(
//         vault.totalAssets(),
//         usdcDepositAmount,
//         "Total assets did not decrease correctly"
//     );
// }
}
