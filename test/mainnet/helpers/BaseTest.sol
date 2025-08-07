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
import {FxProtocolRules} from "script/rules/FxProtocolRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {console} from "lib/forge-std/src/console.sol";
import {WithdrawerConfigurator} from "script/config/WithdrawerConfigurator.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract BaseTest is Test, MainnetActors, TestHelper {
    struct PsPResponse {
        address augustus;
        bytes swapCalldata;
    }

    uint256 public constant MAX_SLIPPAGE = 20; // 0.2% max slippage during swap
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 10000 = 100%
    WrappedToken public wrappedUSDC;

    Withdrawer public withdrawer;

    function deploy() public returns (Vault, Provider) {
        Vault vault = Vault(payable(MC.YNUSDx));
        wrappedUSDC = WrappedToken(MC.WRAPPED_USDC);

        TestHelper._initVault(vault);

        configureMainnet(vault);

        configureFXSave(vault);

        return (vault, Provider(vault.provider()));
    }

    function configureFXSave(Vault vault) internal {
        Provider provider = Provider(0xeb4dBb86cA6aA8f72f863eCEd6d700346fdAC508);

        // // Deploy Withdrawer as an upgradeable proxy
        // address withdrawerImpl = address(new Withdrawer());
        // TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(withdrawerImpl, TIMELOCK, "");
        // withdrawer = Withdrawer(payable(address(proxy)));

        // WithdrawerConfigurator configurator = new WithdrawerConfigurator();
        // configurator.configure(withdrawer, address(provider), TIMELOCK, new MainnetActors());

        withdrawer = Withdrawer(payable(0x3fc3771Cf29b96069644Ea249f3F036069873B4A));
        {
            uint256 BOOTSTRAP_AMOUNT = 1_000e6;
            address bootstrapper = BOOTSTRAPPER;
            vm.startPrank(bootstrapper);
            deal(MC.USDC, bootstrapper, BOOTSTRAP_AMOUNT);
            IERC20(MC.USDC).approve(address(withdrawer), BOOTSTRAP_AMOUNT);
            withdrawer.deposit(BOOTSTRAP_AMOUNT, bootstrapper);
            vm.stopPrank();
        }

        // vm.startPrank(TIMELOCK);

        // vault.setProvider(address(provider));
        // vault.addAsset(MC.FXBASE, false);
        // vault.addAsset(MC.FXUSD, false);
        // vault.addAsset(MC.FXSAVE, false);
        // vault.addAsset(address(withdrawer), false);

        // SafeRules.RuleParams[] memory rules = WithdrawerConfig.getMaxVaultRulesConfiguration(vault, withdrawer);

        // SafeRules.setProcessorRules(vault, rules, true);

        // vm.stopPrank();

        // Call the provided calldata on the timelock contract (MainnetActors.TIMELOCK)
        // This simulates a governance proposal execution or similar privileged action.

        vault.processAccounting();
    }

    function configureMainnet(Vault vault) internal {
        vm.startPrank(TIMELOCK);
        vault.addAsset(MC.GHO, false);
        vault.addAsset(MC.USDE, false);
        vault.addAsset(MC.SUSDE, false);
        vault.addAsset(MC.SCRVUSD, false);
        vault.addAsset(MC.CRVUSD, false);
        vault.addAsset(MC.USDS, false);
        vault.addAsset(MC.SUSDS, false);
        vault.addAsset(MC.SFRAX, false);
        vault.addAsset(MC.FRAX, false);

        vm.stopPrank();

        vault.processAccounting();
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
