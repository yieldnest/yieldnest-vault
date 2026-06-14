// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.23;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {Provider} from "src/module/Provider.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ParaswapValidator} from "src/validator/ParaswapValidator.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ParaswapRules} from "script/rules/ParaswapRules.sol";
import {SuperUsdcRules} from "script/rules/SuperUsdcRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {FeeHooks} from "src/hooks/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {
    ProxyAdmin,
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract BaseTest is Test, MainnetActors, TestHelper {
    struct PsPResponse {
        address augustus;
        bytes swapCalldata;
    }

    uint256 public constant MAX_SLIPPAGE = 20; // 0.2% max slippage during swap
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 10000 = 100%
    WrappedToken public wrappedUSDC;

    function deploy() public returns (Vault, Provider) {
        Vault vault = Vault(payable(MC.YNUSDx));
        wrappedUSDC = WrappedToken(MC.WRAPPED_USDC);

        TestHelper._initVault(vault);

        configureMainnet(vault);

        return (vault, Provider(vault.provider()));
    }

    function configureMainnet(Vault vault) internal {
        vm.startPrank(TIMELOCK);
        _addAssetIfMissing(vault, MC.GHO, false);
        _addAssetIfMissing(vault, MC.USDE, false);
        _addAssetIfMissing(vault, MC.SUSDE, false);
        _addAssetIfMissing(vault, MC.SCRVUSD, false);
        _addAssetIfMissing(vault, MC.CRVUSD, false);
        _addAssetIfMissing(vault, MC.USDS, false);
        _addAssetIfMissing(vault, MC.SUSDS, false);
        _addAssetIfMissing(vault, MC.SFRAX, false);
        _addAssetIfMissing(vault, MC.FRAX, false);
        _addAssetIfMissing(vault, MC.YNUSDC, false);
        _addAssetIfMissing(vault, MC.EVK_VAULT_EUSDC_95, false);

        configureMainnetProcessorRules(vault);

        vm.stopPrank();

        vault.processAccounting();
    }

    function _addAssetIfMissing(Vault vault, address asset, bool active) internal {
        if (!_hasAsset(vault, asset)) {
            vault.addAsset(asset, active);
        }
    }

    function _hasAsset(Vault vault, address asset) internal view returns (bool) {
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == asset) {
                return true;
            }
        }
        return false;
    }

    function configureMainnetProcessorRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](5);
        uint256 i = 0;

        address[] memory usdcApprovalAllowList = new address[](5);
        usdcApprovalAllowList[0] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.SUPER_USDC_VAULT;
        usdcApprovalAllowList[3] = MC.YNUSDC;
        usdcApprovalAllowList[4] = MC.EVK_VAULT_EUSDC_95;

        rules[i++] = BaseRules.getApprovalRule(MC.USDC, usdcApprovalAllowList);
        rules[i++] = BaseRules.getDepositRule(MC.YNUSDC, address(vault));
        rules[i++] = BaseRules.getDepositRule(MC.EVK_VAULT_EUSDC_95, address(vault));
        rules[i++] = BaseRules.getDepositRule(MC.SUPER_USDC_VAULT, address(vault));

        SafeRules.RuleParams[] memory superUsdcRules =
            SuperUsdcRules.getSuperUsdcRedeemRules(MC.SUPER_USDC_VAULT, address(vault));
        for (uint256 j = 0; j < superUsdcRules.length; j++) {
            rules[i++] = superUsdcRules[j];
        }

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, true);
    }

    function configureVaultRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](10);
        uint256 i = 0;

        address[] memory usdcApprovalAllowList = new address[](3);
        usdcApprovalAllowList[0] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.SUPER_USDC_VAULT;
        rules[i++] = BaseRules.getDepositRule(MC.MORPHO_GAUNTLET_USDC_VAULT, address(vault));
        rules[i++] = BaseRules.getDepositRule(address(MC.SUPER_USDC_VAULT), address(vault));
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, usdcApprovalAllowList);
        rules[i++] = BaseRules.getApprovalRule(MC.USDT, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.GHO, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.USDE, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.SUSDE, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.SCRVUSD, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.SUSDS, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.SFRAX, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, false);
    }

    function configureParaswapRules(Vault vault, ParaswapValidator paraswapValidator) internal {
        SafeRules.RuleParams[] memory rules =
            ParaswapRules.getParaswapRules(MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(paraswapValidator));
        SafeRules.setProcessorRules(vault, rules, false);
    }

    function configureSuperUsdcRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules =
            SuperUsdcRules.getSuperUsdcRedeemRules(MC.SUPER_USDC_VAULT, address(vault));
        SafeRules.setProcessorRules(vault, rules, false);
    }

    function _fetchPSPRoute(address from, address to, uint256 amount, address userAddress)
        internal
        returns (PsPResponse memory)
    {
        string[] memory inputs = new string[](11);
        inputs[0] = "node";
        inputs[1] = "test/scripts/paraswap.js";
        inputs[2] = vm.toString(block.chainid);
        inputs[3] = vm.toString(from);
        inputs[4] = vm.toString(to);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(userAddress);
        inputs[7] = vm.toString(MAX_SLIPPAGE);
        inputs[8] = vm.toString(ERC20(from).decimals());
        inputs[9] = vm.toString(ERC20(to).decimals());
        inputs[10] = "false";

        bytes memory res = vm.ffi(inputs);
        return abi.decode(res, (PsPResponse));
    }
}
