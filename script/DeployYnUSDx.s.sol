// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.24;

import {BaseScript} from "script/BaseScript.sol";
import {console} from "lib/forge-std/src/console.sol";

import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {ParaswapValidator} from "src/validator/ParaswapValidator.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ParaswapRules} from "script/rules/ParaswapRules.sol";
import {SuperUsdcRules} from "script/rules/SuperUsdcRules.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";

/**
 * @title DeployYnUSDx
 * @notice Script to deploy the YieldNest USDx vault and configure it for mainnet
 */
contract DeployYnUSDx is BaseScript, MainnetActors {
    // Constants
    uint256 public constant MAX_SLIPPAGE = 20; // 0.2% in basis points
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 100% in basis points

    error InvalidWrappedUSDC();
    error InvalidRateProvider();
    error InvalidTimelock();

    function symbol() public pure override returns (string memory) {
        return "ynUSDx";
    }

    function deployRateProvider(address _wrappedUSDC) internal {
        rateProvider = IProvider(address(new Provider(_wrappedUSDC)));
    }

    function deployWrappedUSDC() internal returns (address) {
        wrappedUSDCImplementation = address(new WrappedToken());

        if (address(timelock) == address(0)) {
            revert InvalidTimelock();
        }

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(wrappedUSDCImplementation), address(timelock), "");
        wrappedUSDCProxy =
            address(new TransparentUpgradeableProxy(address(wrappedUSDCImplementation), address(timelock), ""));
        WrappedToken(wrappedUSDCProxy).initialize(IERC20(MC.USDC), "Wrapped USDC", "wUSDC", 18, 12);

        return address(wrappedUSDCProxy);
    }

    function _verifySetup() public view override {
        super._verifySetup();

        if (wrappedUSDCProxy == address(0)) {
            revert InvalidWrappedUSDC();
        }

        if (address(rateProvider) == address(0)) {
            revert InvalidRateProvider();
        }
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        _deployTimelockController();
        address wrappedUSDCProxy = deployWrappedUSDC();
        deployRateProvider(wrappedUSDCProxy);

        _verifySetup();

        // Deploy and configure the vault system
        deployVaultSystem();
        _saveDeployment();

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the vault system including Vault, BufferStrategy, Provider, and Validators
     */
    function deployVaultSystem() internal {
        address admin = msg.sender;

        vaultImplementation = new Vault();
        vaultProxyAdmin = address(timelock);
        vaultProxy =
            Vault(payable(address(new TransparentUpgradeableProxy(address(vaultImplementation), vaultProxyAdmin, ""))));
        // TODO: set base withdrawal fee parameters correctly
        vaultProxy.initialize(admin, "YieldNest USD Max Vault", "ynUSDx", 18, 0, false, false, 1);

        address[] memory supportedTokensForParaswapValidator = new address[](8);
        supportedTokensForParaswapValidator[0] = MC.USDC;
        supportedTokensForParaswapValidator[1] = MC.USDT;
        supportedTokensForParaswapValidator[2] = MC.GHO;
        supportedTokensForParaswapValidator[3] = MC.USDE;
        supportedTokensForParaswapValidator[4] = MC.CRVUSD;
        supportedTokensForParaswapValidator[5] = MC.USDS;
        supportedTokensForParaswapValidator[6] = MC.FRAX;
        supportedTokensForParaswapValidator[7] = MC.USDS;

        ParaswapValidator paraswapValidator = new ParaswapValidator(
            MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER,
            address(vaultProxy),
            address(rateProvider),
            MAX_SLIPPAGE,
            supportedTokensForParaswapValidator
        );

        // 7. Configure the deployed contracts
        configureVaultSystem(vaultProxy, rateProvider, paraswapValidator);
    }

    /**
     * @notice Configure the vault system after deployment
     * @param vault The deployed Vault contract
     * @param provider The deployed Provider contract
     * @param paraswapValidator The deployed ParaswapValidator contract
     */
    function configureVaultSystem(Vault vault, IProvider provider, ParaswapValidator paraswapValidator) internal {
        // 1. Set up roles for the Vault
        BaseRoles.configureDefaultRoles(vault, address(timelock), actors);
        // 2. Configure temporary roles for the Vault
        BaseRoles.configureTemporaryRoles(vault);

        // 3. Set Provider for Vault
        vault.setProvider(address(provider));

        // 4. Add assets to Vault
        vault.addAsset(address(wrappedUSDCProxy), true);
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

        // 5. Configure rules
        configureVaultRules(vault);
        configureParaswapRules(vault, paraswapValidator);
        configureSuperUsdcRules(vault);

        // 6. Set Buffer for Vault
        vault.setBuffer(MC.MORPHO_GAUNTLET_USDC_VAULT);

        // 7. Unpause contracts
        vault.unpause();

        // 8. Process initial accounting
        vault.processAccounting();

        BaseRoles.renounceTemporaryRoles(vault, deployer);
    }

    /**
     * @notice Configure Vault rules
     * @param vault The Vault contract
     */
    function configureVaultRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](10);
        uint256 i = 0;

        address[] memory usdcApprovalAllowList = new address[](3);
        usdcApprovalAllowList[0] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.SUPER_USDC_VAULT;
        rules[i++] = BaseRules.getDepositRule(MC.MORPHO_GAUNTLET_USDC_VAULT, address(vault));
        rules[i++] = BaseRules.getDepositRule(MC.SUPER_USDC_VAULT, address(vault));
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

    /**
     * @notice Configure ParaswapRules
     * @param vault The Vault contract
     * @param paraswapValidator The ParaswapValidator contract
     */
    function configureParaswapRules(Vault vault, ParaswapValidator paraswapValidator) internal {
        SafeRules.RuleParams[] memory rules =
            ParaswapRules.getParaswapRules(MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(paraswapValidator));
        SafeRules.setProcessorRules(vault, rules, false);
    }

    /**
     * @notice Configure SuperUSDC rules
     * @param vault The Vault contract
     */
    function configureSuperUsdcRules(Vault vault) internal {
        SafeRules.RuleParams[] memory rules =
            SuperUsdcRules.getSuperUsdcRedeemRules(MC.SUPER_USDC_VAULT, address(vault));
        SafeRules.setProcessorRules(vault, rules, false);
    }
}
