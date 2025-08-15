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
import {console} from "lib/forge-std/src/console.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Hooks} from "src/Hooks.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract Vault6DecimalsBaseHooksUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;
    Hooks public hooks;

    WrappedToken public wusdc;

    function setUp() public {
        SetupBase6DecimalsVault setupVault = new SetupBase6DecimalsVault();
        (vault,) = setupVault.setup();
        wusdc = setupVault.wusdc();
        hooks = Hooks(address(vault.hooks()));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
    }

    function test_AfterProcessAccounting_Invariants(uint256 totalAssetsBefore, uint256 totalAssetsAfter) public {
        totalAssetsBefore = bound(totalAssetsBefore, 1 * 10 ** 6, 1_000_000 * 10 ** 6);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 100 * 10 ** 6, 1_000_101 * 10 ** 6);

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 6);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        donationAmount = donationAmount;
        deal((MC.USDC), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.USDC).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.USDC).transfer(address(vault), donationAmount);
        vm.stopPrank();

        vm.startPrank(address(vault));
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultTotalAssetsBefore = vault.totalAssets();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        uint256 feesAccrued = (donationAmount * hooks.performanceFee()) / 1 ether;
        vm.stopPrank();

        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());
        uint256 vaultTotalAssetsAfter = vault.totalAssets();

        if (feesAccrued > 0) {
            uint256 performanceFeeShares = vaultTotalSupplyAfter - vaultTotalSupplyBefore;
            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeShares),
                feesAccrued,
                1e2,
                "performance fee shares should be equal to performance fee amount"
            );
            assertGt(
                vaultTotalSupplyAfter,
                vaultTotalSupplyBefore,
                "vault's total supply should increase due to fee shares minted"
            );
            assertGt(
                vaultTotalAssetsAfter,
                vaultTotalAssetsBefore,
                "vault's total assets should increase due to fee shares minted"
            );
            assertGt(
                vaultExchangeRateAfter,
                vaultExchangeRateBefore,
                "vault's exchange rate should always increase due to donation"
            );
        } else {
            assertEq(
                vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee"
            );
        }

        vm.stopPrank();
    }

    function test_AfterProcessingAccountWithNoPerformanceFee(uint256 totalAssetsBefore, uint256 totalAssetsAfter)
        public
    {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0);
        vm.stopPrank();

        totalAssetsBefore = bound(totalAssetsBefore, 1 * 10 ** 6, 1_000_000 * 10 ** 6);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 100 * 10 ** 6, 1_000_101 * 10 ** 6);

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 6);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        donationAmount = donationAmount;
        deal((MC.USDC), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.USDC).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.USDC).transfer(address(vault), donationAmount);
        vm.stopPrank();

        vm.startPrank(address(vault));
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultTotalAssetsBefore = vault.totalAssets();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());

        hooks.afterProcessAccounting(totalAssetsBefore, totalAssetsAfter, vaultTotalSupplyBefore, 0, 0, 0);
        vm.stopPrank();
        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());
        uint256 vaultTotalAssetsAfter = vault.totalAssets();

        assertEq(vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee");
        assertGt(
            vaultExchangeRateAfter,
            vaultExchangeRateBefore,
            "vault's exchange rate should always increase due to donation"
        );
        assertGt(
            vaultTotalAssetsAfter, vaultTotalAssetsBefore, "vault's total assets should always increase due to donation"
        );
        vm.stopPrank();
    }
}
