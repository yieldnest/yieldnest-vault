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
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ParaswapRules} from "script/rules/ParaswapRules.sol";
import {SuperUsdcRules} from "script/rules/SuperUsdcRules.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";

/**
 * @title DeployYnUSDx
 * @notice Script to deploy the YieldNest USDx vault and configure it for mainnet
 */
contract DeployYnUSDx is BaseScript, MainnetActors {
    // Constants
    uint256 public constant MAX_SLIPPAGE = 20; // 0.2% in basis points
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 100% in basis points

    error InvalidRateProvider();
    error InvalidTimelock();

    function symbol() public pure override returns (string memory) {
        return "ynUSDx";
    }

    function deployRateProvider() internal {
        rateProvider = IProvider(address(new Provider(MC.WRAPPED_USDC)));
    }

    function _verifySetup() public view override {
        super._verifySetup();

        if (address(rateProvider) == address(0)) {
            revert InvalidRateProvider();
        }
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        _deployTimelockController();
        deployRateProvider();

        _verifySetup();

        // Deploy and configure the vault system
        deployVaultSystem();
        _deployViewer();
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
        vaultProxy.initialize(admin, "ynUSD Max", "ynUSDx", 18, 100000, false, false, 1);

        address[] memory supportedTokensForParaswapValidator = new address[](8);
        supportedTokensForParaswapValidator[0] = MC.USDC;
        supportedTokensForParaswapValidator[1] = MC.USDT;
        supportedTokensForParaswapValidator[2] = MC.GHO;
        supportedTokensForParaswapValidator[3] = MC.USDE;
        supportedTokensForParaswapValidator[4] = MC.CRVUSD;
        supportedTokensForParaswapValidator[5] = MC.USDS;
        supportedTokensForParaswapValidator[6] = MC.FRAX;
        supportedTokensForParaswapValidator[7] = MC.USDS;

        ParaswapValidator _paraswapValidator = new ParaswapValidator(
            MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER,
            address(vaultProxy),
            address(rateProvider),
            MAX_SLIPPAGE,
            supportedTokensForParaswapValidator
        );

        paraswapValidator = address(_paraswapValidator);

        // 7. Configure the deployed contracts
        configureVaultSystem(vaultProxy, rateProvider);
    }

    function _deployViewer() internal {
        viewerImplementation = new MaxVaultViewer();

        viewerProxy = IVaultViewer(
            payable(address(new TransparentUpgradeableProxy(address(viewerImplementation), actors.ADMIN(), "")))
        );

        MaxVaultViewer(payable(address(viewerProxy))).initialize(address(vaultProxy), msg.sender);

        MaxVaultViewer maxVaultViewer = MaxVaultViewer(payable(address(viewerProxy)));

        maxVaultViewer.grantRole(maxVaultViewer.UPDATER_ROLE(), actors.UPDATER());
        maxVaultViewer.grantRole(maxVaultViewer.DEFAULT_ADMIN_ROLE(), actors.ADMIN());

        maxVaultViewer.grantRole(maxVaultViewer.UPDATER_ROLE(), msg.sender);
        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = MC.USDC;
        maxVaultViewer.addUnderlyingAssets(underlyingAssets);

        maxVaultViewer.renounceRole(maxVaultViewer.DEFAULT_ADMIN_ROLE(), msg.sender);
        maxVaultViewer.renounceRole(maxVaultViewer.UPDATER_ROLE(), msg.sender);
    }

    /**
     * @notice Configure the vault system after deployment
     * @param vault The deployed Vault contract
     * @param provider The deployed Provider contract
     */
    function configureVaultSystem(Vault vault, IProvider provider) internal {
        // 1. Set up roles for the Vault
        BaseRoles.configureDefaultRoles(vault, address(timelock), actors);
        // 2. Configure temporary roles for the Vault
        BaseRoles.configureTemporaryRoles(vault, deployer);

        // 3. Set Provider for Vault
        vault.setProvider(address(provider));

        // 4. Add assets to Vault
        vault.addAsset(MC.WRAPPED_USDC, false);
        vault.addAsset(MC.USDC, true);
        vault.addAsset(MC.MORPHO_GAUNTLET_USDC_VAULT, false);
        vault.addAsset(MC.USDT, false);
        // vault.addAsset(MC.GHO, false);
        // vault.addAsset(MC.USDE, false);
        // vault.addAsset(MC.SUSDE, false);
        // vault.addAsset(MC.SCRVUSD, false);
        // vault.addAsset(MC.CRVUSD, false);
        // vault.addAsset(MC.USDS, false);
        // vault.addAsset(MC.SUSDS, false);
        // vault.addAsset(MC.SFRAX, false);
        // vault.addAsset(MC.FRAX, false);
        vault.addAsset(MC.SUPER_USDC_VAULT, false);

        // 5. Configure rules
        configureVaultRules(vault);

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
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](11);
        uint256 i = 0;

        address[] memory usdcApprovalAllowList = new address[](3);
        usdcApprovalAllowList[0] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.SUPER_USDC_VAULT;
        // set deposit rules
        rules[i++] = BaseRules.getDepositRule(MC.MORPHO_GAUNTLET_USDC_VAULT, address(vault));
        rules[i++] = BaseRules.getDepositRule(MC.SUPER_USDC_VAULT, address(vault));
        // set approval rules
        rules[i++] = BaseRules.getApprovalRule(MC.USDC, usdcApprovalAllowList);
        // set paraswap rules
        SafeRules.RuleParams[] memory paraswapRules =
            ParaswapRules.getParaswapRules(MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(paraswapValidator));
        for (uint256 j = 0; j < paraswapRules.length; j++) {
            rules[i++] = paraswapRules[j];
        }
        // set super usdc rules
        SafeRules.RuleParams[] memory superUsdcRules =
            SuperUsdcRules.getSuperUsdcRedeemRules(MC.SUPER_USDC_VAULT, address(vault));
        for (uint256 j = 0; j < superUsdcRules.length; j++) {
            rules[i++] = superUsdcRules[j];
        }
        rules[i++] = BaseRules.getApprovalRule(MC.USDT, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        // rules[i++] = BaseRules.getApprovalRule(MC.GHO, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        // rules[i++] = BaseRules.getApprovalRule(MC.USDE, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        // rules[i++] = BaseRules.getApprovalRule(MC.SUSDE, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        // rules[i++] = BaseRules.getApprovalRule(MC.SCRVUSD, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        // rules[i++] = BaseRules.getApprovalRule(MC.SUSDS, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);
        // rules[i++] = BaseRules.getApprovalRule(MC.SFRAX, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, false);
    }
}
