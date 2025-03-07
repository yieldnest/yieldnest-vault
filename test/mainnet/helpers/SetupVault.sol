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

import {Etches} from "test/mainnet/helpers/Etches.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";

contract SetupVault is Test, MainnetActors, Etches {

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    uint256 public pid = 40; // TODO: Update with pid specific to SCRVUSD-SUSDE pool
    string public name = "SCRVUSD-SUSDE";

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

        assertEq(vault.symbol(), "ynUSDx");
        
        BufferStrategy bufferStrategyImplementation = new BufferStrategy();
        bytes memory bufferStrategyInitData = abi.encodeWithSelector(
            BufferStrategy.initialize.selector, MainnetActors.ADMIN, "Buffer Strategy", "Buffer Strategy", 18, 0, false, true
        );
        TransparentUpgradeableProxy bufferStrategyProxy =
            new TransparentUpgradeableProxy(address(bufferStrategyImplementation), address(MainnetActors.ADMIN), bufferStrategyInitData);

        BufferStrategy bufferStrategy = BufferStrategy(payable(address(bufferStrategyProxy)));
        Provider provider = new Provider();

        // IStrategyInterface convexStakerStrategy = IStrategyInterface(address(new StrategyConvexStaker(MC.CURVE_LP_SCRVUSD_SUSDE_POOL, pid, MC.CONVEX_BOOSTER, name)));

        configureMainnet(vault, bufferStrategy, provider
        // , convexStakerStrategy
        );

        return (vault, bufferStrategy, provider);
    }

    function configureMainnet(Vault vault, BufferStrategy bufferStrategy, Provider provider
    // , IStrategyInterface convexStakerStrategy
    ) internal {
        
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

        bufferStrategy.addAsset(MC.USDC, 6, true, true);
        bufferStrategy.addAsset(MC.MORPHO_GAUNTLET_USDC_VAULT, false, false);
        bufferStrategy.setProvider(address(provider));
        bufferStrategy.setUsdcCoreVault(MC.MORPHO_GAUNTLET_USDC_VAULT);
        bufferStrategy.setSyncDeposit(true);
        bufferStrategy.setSyncWithdraw(true);

        configureVaultRules(vault, bufferStrategy);
        configureBufferStrategyRules(bufferStrategy);

        vault.setBuffer(address(bufferStrategy));

        // Unpause the vault
        vault.unpause();
        bufferStrategy.unpause();

        vm.stopPrank();

        vault.processAccounting();


    }

    function configureVaultRules(Vault vault, BufferStrategy bufferStrategy) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](9);
        uint256 i = 0;

        address[] memory usdcApprovalAllowList = new address[](3);
        usdcApprovalAllowList[0] = address(bufferStrategy);
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        rules[i++] = BaseRules.getDepositRule(address(bufferStrategy), address(vault));
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

    function configureBufferStrategyRules(BufferStrategy bufferStrategy) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        uint256 i = 0;

        rules[i++] = BaseRules.getDepositRule(address(MC.MORPHO_GAUNTLET_USDC_VAULT), address(bufferStrategy));
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, address(MC.MORPHO_GAUNTLET_USDC_VAULT));
    }
}