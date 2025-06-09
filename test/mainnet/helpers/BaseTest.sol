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
import {console} from "lib/forge-std/src/console.sol";

contract BaseTest is Test, MainnetActors, TestHelper {
    struct PsPResponse {
        address augustus;
        bytes swapCalldata;
    }

    uint256 public constant MAX_SLIPPAGE = 20; // 0.2% max slippage during swap
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 10000 = 100%
    WrappedToken public wrappedUSDC;

    function deploy() public returns (Vault, Provider) {
        // Deploy implementation contract
        Vault vaultImplementation = new Vault();
        Vault vault = Vault(
            payable(
                address(new TransparentUpgradeableProxy(address(vaultImplementation), address(MainnetActors.ADMIN), ""))
            )
        );
        vault.initialize(MainnetActors.ADMIN, "YieldNest USD Max Vault", "ynUSDx", 18, 0, false, false, 1);

        wrappedUSDC =
            WrappedToken(address(new TransparentUpgradeableProxy(address(new WrappedToken()), MainnetActors.ADMIN, "")));
        wrappedUSDC.initialize(ERC20(MC.USDC), "Wrapped USDC", "wUSDC", 18, 12);

        TestHelper._initVault(vault);

        address[] memory supportedTokens = new address[](8);
        supportedTokens[0] = MC.USDC;
        supportedTokens[1] = MC.USDT;
        supportedTokens[2] = MC.GHO;
        supportedTokens[3] = MC.USDE;
        supportedTokens[4] = MC.CRVUSD;
        supportedTokens[5] = MC.USDS;
        supportedTokens[6] = MC.FRAX;
        supportedTokens[7] = MC.USDS;

        Provider provider = new Provider(address(wrappedUSDC));
        ParaswapValidator paraswapValidator = new ParaswapValidator(
            MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(vault), address(provider), MAX_SLIPPAGE, supportedTokens
        );

        configureMainnet(vault, provider, paraswapValidator);

        return (vault, provider);
    }

    function configureMainnet(Vault vault, Provider provider, ParaswapValidator paraswapValidator) internal {
        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);

        // test cannot unpause vault without provider
        vm.expectRevert();
        vault.unpause();

        vault.setProvider(address(provider));

        vault.addAsset(address(wrappedUSDC), true);
        vault.addAsset(MC.USDC, true);
        vault.addAsset(MC.MORPHO_GAUNTLET_USDC_VAULT, false);
        vault.addAsset(MC.USDT, false);
        vault.addAsset(MC.GHO, false);
        vault.addAsset(MC.USDE, false);
        vault.addAsset(MC.SUSDE, false);
        vault.addAsset(MC.SCRVUSD, false);
        vault.addAsset(MC.CRVUSD, false);
        vault.addAsset(MC.USDS, false);
        vault.addAsset(MC.SUSDS, false);
        vault.addAsset(MC.SFRAX, false);
        vault.addAsset(MC.FRAX, false);
        vault.addAsset(MC.SUPER_USDC_VAULT, false);

        configureVaultRules(vault);
        configureParaswapRules(vault, paraswapValidator);
        configureSuperUsdcRules(vault);

        vault.setBuffer(MC.MORPHO_GAUNTLET_USDC_VAULT);

        // Unpause the vault and buffer strategy
        vault.unpause();

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
