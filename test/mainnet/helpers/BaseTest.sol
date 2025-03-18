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
import {BufferStrategy} from "src/BufferStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ParaswapValidator} from "src/validator/ParaswapValidator.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";

import {Etches} from "test/mainnet/helpers/Etches.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ParaswapRules} from "script/rules/ParaswapRules.sol";
import {SuperUsdcRules} from "script/rules/SuperUsdcRules.sol";
import {console} from "lib/forge-std/src/console.sol";

contract BaseTest is Test, MainnetActors, Etches, TestHelper {

    struct PsPResponse {
        address augustus;
        bytes swapCalldata;
    }

    uint256 public constant MAX_SLIPPAGE = 1000;
    uint256 public constant SLIPPAGE_PRECISION = 10000;

    function deploy() public returns (Vault, BufferStrategy, Provider) {
        // Deploy implementation contract
        Vault vaultImplementation = new Vault();

        // Deploy transparent proxy
        bytes memory vaultInitData = abi.encodeWithSelector(
            Vault.initialize.selector, MainnetActors.ADMIN, "ynUSDx", "ynUSDx", 18, 0, false, true
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), address(MainnetActors.ADMIN), vaultInitData);

        // Cast proxy to Vault type
        Vault vault = Vault(payable(address(proxy)));

        TestHelper._initVault(vault);

        assertEq(vault.symbol(), "ynUSDx");
        
        BufferStrategy bufferStrategyImplementation = new BufferStrategy();
        bytes memory bufferStrategyInitData = abi.encodeWithSelector(
            BufferStrategy.initialize.selector, MainnetActors.ADMIN, "Buffer Strategy", "Buffer Strategy", 18, 0, false, true
        );
        TransparentUpgradeableProxy bufferStrategyProxy =
            new TransparentUpgradeableProxy(address(bufferStrategyImplementation), address(MainnetActors.ADMIN), bufferStrategyInitData);

        address[] memory supportedTokens = new address[](8);
        supportedTokens[0] = MC.USDC;
        supportedTokens[1] = MC.USDT;
        supportedTokens[2] = MC.GHO;
        supportedTokens[3] = MC.USDE;
        supportedTokens[4] = MC.SUSDE;
        supportedTokens[5] = MC.SCRVUSD;
        supportedTokens[6] = MC.SUSDS;
        supportedTokens[7] = MC.SFRAX;

        BufferStrategy bufferStrategy = BufferStrategy(payable(address(bufferStrategyProxy)));
        Provider provider = new Provider();
        ParaswapValidator paraswapValidator = new ParaswapValidator(MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(vault), address(provider), MAX_SLIPPAGE, supportedTokens);
        
        configureMainnet(vault, bufferStrategy, provider, paraswapValidator);

        return (vault, bufferStrategy, provider);
    }

    function configureMainnet(Vault vault, BufferStrategy bufferStrategy, Provider provider, ParaswapValidator paraswapValidator) internal {
        
        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);

        bufferStrategy.grantRole(bufferStrategy.PROCESSOR_ROLE(), PROCESSOR);
        bufferStrategy.grantRole(bufferStrategy.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.PAUSER_ROLE(), PAUSER);
        bufferStrategy.grantRole(bufferStrategy.UNPAUSER_ROLE(), UNPAUSER);
        bufferStrategy.grantRole(bufferStrategy.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.MORPHO_USDC_CORE_VAULT_MANAGER_ROLE(), MORPHO_USDC_CORE_VAULT_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.DEPOSIT_MANAGER_ROLE(), DEPOSIT_MANAGER);

        // test cannot unpause vault without provider
        vm.expectRevert();
        vault.unpause();

        vault.setProvider(address(provider));

        // Add assets: Base asset always first
        vault.addAsset(MC.USDC, true);
        vault.addAsset(address(bufferStrategy), false);
        vault.addAsset(MC.USDT, false);
        vault.addAsset(MC.GHO, false);
        vault.addAsset(MC.USDE, false);
        vault.addAsset(MC.SUSDE, false);
        vault.addAsset(MC.SCRVUSD, false);
        vault.addAsset(MC.SUSDS, false);
        vault.addAsset(MC.SFRAX, false);
        vault.addAsset(MC.SUPER_USDC_VAULT, false);

        bufferStrategy.addAsset(MC.USDC, 6, true, true);
        bufferStrategy.addAsset(MC.MORPHO_GAUNTLET_USDC_VAULT, false, false);
        bufferStrategy.setProvider(address(provider));
        bufferStrategy.setUsdcCoreVault(MC.MORPHO_GAUNTLET_USDC_VAULT);
        bufferStrategy.setSyncDeposit(true);
        bufferStrategy.setSyncWithdraw(true);

        configureVaultRules(vault, bufferStrategy);
        configureBufferStrategyRules(bufferStrategy);
        configureParaswapRules(vault, paraswapValidator);
        configureSuperUsdcRules(vault);

        vault.setBuffer(address(bufferStrategy));

        // Unpause the vault
        vault.unpause();
        bufferStrategy.unpause();

        vm.stopPrank();

        vault.processAccounting();


    }

    function configureVaultRules(Vault vault, BufferStrategy bufferStrategy) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](10);
        uint256 i = 0;

        address[] memory usdcApprovalAllowList = new address[](4);
        usdcApprovalAllowList[0] = address(bufferStrategy);
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        usdcApprovalAllowList[3] = MC.SUPER_USDC_VAULT;
        rules[i++] = BaseRules.getDepositRule(address(bufferStrategy), address(vault));
        rules[i++] = BaseRules.getDepositRule(address(MC.SUPER_USDC_VAULT), address(vault));
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, usdcApprovalAllowList);
        address[] memory usdtApprovalAllowList = new address[](2);
        usdtApprovalAllowList[0] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdtApprovalAllowList[1] = 0x16C6521Dff6baB339122a0FE25a9116693265353;
        rules[i++] = BaseRules.getApprovalRule(MC.USDT, usdtApprovalAllowList);
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
        SafeRules.RuleParams[] memory rules = ParaswapRules.getParaswapRules(MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(paraswapValidator));
        SafeRules.setProcessorRules(vault, rules, false);
    }

    function configureBufferStrategyRules(BufferStrategy bufferStrategy) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        uint256 i = 0;

        rules[i++] = BaseRules.getDepositRule(address(MC.MORPHO_GAUNTLET_USDC_VAULT), address(bufferStrategy));
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, address(MC.MORPHO_GAUNTLET_USDC_VAULT));
    }

    function configureSuperUsdcRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules = SuperUsdcRules.getSuperUsdcRedeemRules(MC.SUPER_USDC_VAULT, address(vault));
        SafeRules.setProcessorRules(vault, rules, false);
    }

    function _fetchPSPRoute(
        address from,
        address to,
        uint256 amount,
        address userAddress
    ) internal returns (PsPResponse memory) {
        console.log("amount is", amount);
        console.log("from is", from);
        string[] memory inputs = new string[](11);
        inputs[0] = 'node';
        inputs[1] = 'test/scripts/paraswap.js';
        inputs[2] = vm.toString(block.chainid);
        inputs[3] = vm.toString(from);
        inputs[4] = vm.toString(to);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(userAddress);
        inputs[7] = vm.toString(MAX_SLIPPAGE);
        inputs[8] = vm.toString(ERC20(from).decimals());
        inputs[9] = vm.toString(ERC20(to).decimals());
        inputs[10] = 'false';

    bytes memory res = vm.ffi(inputs);
    return abi.decode(res, (PsPResponse));
  }
}