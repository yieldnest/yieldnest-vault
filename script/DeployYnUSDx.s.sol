// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";

import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {ParaswapValidator} from "src/validator/ParaswapValidator.sol";

import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ParaswapRules} from "script/rules/ParaswapRules.sol";
import {SuperUsdcRules} from "script/rules/SuperUsdcRules.sol";

/**
 * @title DeployYnUSDx
 * @notice Script to deploy the YieldNest USDx vault and configure it for mainnet
 */
contract DeployYnUSDx is Script, MainnetActors {
    // Constants
    uint256 public constant MAX_SLIPPAGE = 100; // 1% in basis points
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 100% in basis points

    // Deployed contract addresses for verification and logging
    address public vaultProxy;
    address public vaultImplementation;
    address public bufferStrategyProxy;
    address public bufferStrategyImplementation;
    address public providerAddress;
    address public paraswapValidatorAddress;
    address public deployer;

    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployer = vm.addr(deployerPrivateKey);

        // Deploy and configure the vault system
        (
            Vault vault, 
            BufferStrategy bufferStrategy, 
            Provider provider,
            ParaswapValidator paraswapValidator
        ) = deployVaultSystem();

        // Log deployed contract addresses
        console.log("Vault Proxy:", address(vault));
        console.log("Vault Implementation:", vaultImplementation);
        console.log("Buffer Strategy Proxy:", address(bufferStrategy));
        console.log("Buffer Strategy Implementation:", bufferStrategyImplementation);
        console.log("Provider:", address(provider));
        console.log("Paraswap Validator:", address(paraswapValidator));

        // Store addresses for verification
        vaultProxy = address(vault);
        bufferStrategyProxy = address(bufferStrategy);
        providerAddress = address(provider);
        paraswapValidatorAddress = address(paraswapValidator);

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the vault system including Vault, BufferStrategy, Provider, and Validators
     * @return Deployed contracts
     */
    function deployVaultSystem() internal returns (
        Vault, 
        BufferStrategy, 
        Provider, 
        ParaswapValidator
    ) {

        Vault _vaultImplementation = new Vault();
        vaultImplementation = address(_vaultImplementation);

        bytes memory vaultInitData = abi.encodeWithSelector(
            Vault.initialize.selector, 
            deployer, 
            "ynUSD MAX", 
            "ynUSDx", 
            6, 
            0,  // todo: to be set
            false, 
            true
        );
        
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(
            address(vaultImplementation), 
            address(MainnetActors.ADMIN), 
            vaultInitData
        );
        Vault vault = Vault(payable(address(vaultProxy)));

        BufferStrategy _bufferStrategyImplementation = new BufferStrategy();
        bufferStrategyImplementation = address(_bufferStrategyImplementation);

        bytes memory bufferStrategyInitData = abi.encodeWithSelector(
            BufferStrategy.initialize.selector, 
            deployer, 
            "Gauntlet USDC Core", 
            "ynUSDx buffer", // todo: do we follow any naming convention here 
            6
        );
        
        TransparentUpgradeableProxy bufferStrategyProxy = new TransparentUpgradeableProxy(
            address(bufferStrategyImplementation), 
            address(MainnetActors.ADMIN), 
            bufferStrategyInitData
        );
        BufferStrategy bufferStrategy = BufferStrategy(payable(address(bufferStrategyProxy)));

        Provider provider = new Provider();

        address[] memory supportedTokensForParaswapValidator = new address[](7);
        supportedTokensForParaswapValidator[0] = MC.USDC;
        supportedTokensForParaswapValidator[1] = MC.USDT;
        supportedTokensForParaswapValidator[2] = MC.GHO;
        supportedTokensForParaswapValidator[3] = MC.USDE;
        supportedTokensForParaswapValidator[4] = MC.CRVUSD;
        supportedTokensForParaswapValidator[5] = MC.USDS;
        supportedTokensForParaswapValidator[6] = MC.FRAX;

        ParaswapValidator paraswapValidator = new ParaswapValidator(
            MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, 
            address(vault), 
            address(provider), 
            MAX_SLIPPAGE, 
            supportedTokensForParaswapValidator
        );

        // 7. Configure the deployed contracts
        configureVaultSystem(vault, bufferStrategy, provider, paraswapValidator);

        return (vault, bufferStrategy, provider, paraswapValidator);
    }

    /**
     * @notice Configure the vault system after deployment
     * @param vault The deployed Vault contract
     * @param bufferStrategy The deployed BufferStrategy contract
     * @param provider The deployed Provider contract
     * @param paraswapValidator The deployed ParaswapValidator contract
     */
    function configureVaultSystem(
        Vault vault, 
        BufferStrategy bufferStrategy, 
        Provider provider, 
        ParaswapValidator paraswapValidator
    ) internal {
        // 1. Set up roles for the Vault
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN);
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);

        // 2. Set up roles for the BufferStrategy
        bufferStrategy.grantRole(bufferStrategy.DEFAULT_ADMIN_ROLE(), ADMIN);
        bufferStrategy.grantRole(bufferStrategy.PROCESSOR_ROLE(), PROCESSOR);
        bufferStrategy.grantRole(bufferStrategy.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.PAUSER_ROLE(), PAUSER);
        bufferStrategy.grantRole(bufferStrategy.UNPAUSER_ROLE(), UNPAUSER);
        bufferStrategy.grantRole(bufferStrategy.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.MORPHO_USDC_CORE_VAULT_MANAGER_ROLE(), MORPHO_USDC_CORE_VAULT_MANAGER);
        bufferStrategy.grantRole(bufferStrategy.DEPOSIT_MANAGER_ROLE(), DEPOSIT_MANAGER);

        // 3. Set Provider for Vault
        vault.setProvider(address(provider));

        // 4. Add assets to Vault
        vault.addAsset(MC.USDC, true); // Base asset
        vault.addAsset(address(bufferStrategy), false);
        vault.addAsset(MC.USDT, false);
        vault.addAsset(MC.GHO, false);
        vault.addAsset(MC.USDE, false);
        vault.addAsset(MC.SUSDE, false);
        vault.addAsset(MC.SCRVUSD, false);
        vault.addAsset(MC.SUSDS, false);
        vault.addAsset(MC.SFRAX, false);
        vault.addAsset(MC.SUPER_USDC_VAULT, false);

        // 5. Configure BufferStrategy
        bufferStrategy.addAsset(MC.USDC, 6, true, true);
        bufferStrategy.addAsset(MC.MORPHO_GAUNTLET_USDC_VAULT, false, false);
        bufferStrategy.setProvider(address(provider));
        bufferStrategy.setUsdcCoreVault(MC.MORPHO_GAUNTLET_USDC_VAULT);
        bufferStrategy.setSyncDeposit(true);
        bufferStrategy.setSyncWithdraw(true);

        // 6. Configure rules
        configureVaultRules(vault, bufferStrategy);
        configureBufferStrategyRules(bufferStrategy);
        configureParaswapRules(vault, paraswapValidator);
        configureSuperUsdcRules(vault);

        // 7. Set Buffer for Vault
        vault.setBuffer(address(bufferStrategy));

        // 8. Unpause contracts
        vault.unpause();
        bufferStrategy.unpause();

        // 9. Process initial accounting
        vault.processAccounting();
    }

    /**
     * @notice Configure Vault rules
     * @param vault The Vault contract
     * @param bufferStrategy The BufferStrategy contract
     */
    function configureVaultRules(Vault vault, BufferStrategy bufferStrategy) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](9);
        uint256 i = 0;

        // USDC approval rules
        address[] memory usdcApprovalAllowList = new address[](3);
        usdcApprovalAllowList[0] = address(bufferStrategy);
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.SUPER_USDC_VAULT;
        
        // Buffer and SuperUSDC deposit rules
        rules[i++] = BaseRules.getDepositRule(address(bufferStrategy), address(vault));
        rules[i++] = BaseRules.getDepositRule(address(MC.SUPER_USDC_VAULT), address(vault));
        
        // Asset approval rules
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, usdcApprovalAllowList);
        rules[i++] = BaseRules.getApprovalRule(MC.USDT, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.GHO, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.USDE, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.CRVUSD, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.USDS, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        rules[i++] = BaseRules.getApprovalRule(MC.FRAX, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, false);
    }

    /**
     * @notice Configure ParaswapRules
     * @param vault The Vault contract
     * @param paraswapValidator The ParaswapValidator contract
     */
    function configureParaswapRules(Vault vault, ParaswapValidator paraswapValidator) internal {
        SafeRules.RuleParams[] memory rules = ParaswapRules.getParaswapRules(
            MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, 
            address(paraswapValidator)
        );
        SafeRules.setProcessorRules(vault, rules, false);
    }

    /**
     * @notice Configure BufferStrategy rules
     * @param bufferStrategy The BufferStrategy contract
     */
    function configureBufferStrategyRules(BufferStrategy bufferStrategy) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        uint256 i = 0;

        rules[i++] = BaseRules.getDepositRule(address(MC.MORPHO_GAUNTLET_USDC_VAULT), address(bufferStrategy));
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, address(MC.MORPHO_GAUNTLET_USDC_VAULT));
        
        SafeRules.setProcessorRules(bufferStrategy, rules, false);
    }

    /**
     * @notice Configure SuperUSDC rules
     * @param vault The Vault contract
     */
    function configureSuperUsdcRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules = SuperUsdcRules.getSuperUsdcRedeemRules(
            MC.SUPER_USDC_VAULT, 
            address(vault)
        );
        SafeRules.setProcessorRules(vault, rules, false);
    }
} 