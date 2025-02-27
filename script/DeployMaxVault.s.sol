// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {Provider, IProvider} from "src/module/Provider.sol";
import {IVault} from "src/interface/IVault.sol";
import {TestProvider} from "test/module/TestProvider.sol";

import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FeeMath} from "src/module/FeeMath.sol";
import {BaseScript} from "script/BaseScript.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployMaxVault
contract DeployMaxVault is BaseScript {
    error InvalidRules();

    function symbol() public pure override returns (string memory) {
        return "ynBNBx";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(new TestProvider());
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(new Provider());
        }
    }

    function _verifySetup() public view override {
        super._verifySetup();

        if (contracts.YNWBNBK() == address(0x0b)) {
            revert InvalidSetup();
        }
        if (block.chainid == 56 && contracts.YNCLISBNBK() == address(0x0c)) {
            // YNCLISBNBK is required only on bsc mainnet
            revert InvalidSetup();
        }
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        _deployTimelockController();
        deployRateProvider();

        _verifySetup();

        deploy();

        _deployViewer();

        _saveDeployment();

        vm.stopBroadcast();
    }

    function _deployViewer() internal {
        MaxVaultViewer viewerImpl = new MaxVaultViewer();

        viewerImplementation = IVaultViewer(payable(address(viewerImpl)));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(viewerImplementation), actors.ADMIN(), "");

        MaxVaultViewer(payable(address(proxy))).initialize(address(vault), msg.sender);

        viewer = IVaultViewer(payable(address(proxy)));

        MaxVaultViewer maxVaultViewer = MaxVaultViewer(payable(address(viewer)));

        maxVaultViewer.grantRole(maxVaultViewer.UPDATER_ROLE(), actors.UPDATER());
        maxVaultViewer.grantRole(maxVaultViewer.DEFAULT_ADMIN_ROLE(), actors.ADMIN());

        maxVaultViewer.grantRole(maxVaultViewer.UPDATER_ROLE(), msg.sender);
        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = contracts.WBNB();
        maxVaultViewer.addUnderlyingAssets(underlyingAssets);

        maxVaultViewer.renounceRole(maxVaultViewer.DEFAULT_ADMIN_ROLE(), msg.sender);
        maxVaultViewer.renounceRole(maxVaultViewer.UPDATER_ROLE(), msg.sender);
    }

    function deploy() internal {
        implementation = new Vault();

        address admin = msg.sender;

        string memory name = "ynBNB MAX";
        string memory symbol_ = "ynBNBx";
        uint8 decimals = 18;

        uint64 baseWithdrawalFee = uint64(0.001 ether * FeeMath.BASIS_POINT_SCALE / 1 ether); // 0.1%

        bool countNativeAsset = true;
        bool alwaysComputeTotalAssets = true;

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), "");

        vault = Vault(payable(address(proxy)));

        vault.initialize(admin, name, symbol_, decimals, baseWithdrawalFee, countNativeAsset, alwaysComputeTotalAssets);

        configureVault();
    }

    function configureVault() internal {
        BaseRoles.configureDefaultRolesForMaxVault(vault, address(timelock), actors);
        BaseRoles.configureTemporaryRolesForMaxVault(vault, deployer);

        // set provider
        vault.setProvider(address(rateProvider));

        // add assets
        vault.addAsset(contracts.WBNB(), true);
        vault.addAsset(contracts.YNWBNBK(), false);

        // ynclisbnbk only for bnb mainnet
        if (block.chainid == 56) {
            vault.addAsset(contracts.YNCLISBNBK(), false);
        }

        // buffer or ynwbnbk
        vault.setBuffer(contracts.YNWBNBK());

        uint256 rulesLength = block.chainid == 56 ? 11 : 7;
        uint256 i = 0;

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](rulesLength);

        rules[i++] = BaseRules.getDepositRule(contracts.YNWBNBK(), address(vault));
        rules[i++] = BaseRules.getWithdrawRule(contracts.YNWBNBK(), address(vault));
        rules[i++] = BaseRules.getDepositAssetRule(contracts.YNWBNBK(), contracts.WBNB(), address(vault));
        rules[i++] = BaseRules.getWithdrawAssetRule(contracts.YNWBNBK(), contracts.WBNB(), address(vault));

        // ynclisbnbk only for bnb mainnet
        if (block.chainid == 56) {
            rules[i++] = BaseRules.getDepositRule(contracts.YNCLISBNBK(), address(vault));
            rules[i++] = BaseRules.getWithdrawRule(contracts.YNCLISBNBK(), address(vault));
            rules[i++] = BaseRules.getDepositAssetRule(contracts.YNCLISBNBK(), contracts.WBNB(), address(vault));
            rules[i++] = BaseRules.getWithdrawAssetRule(contracts.YNCLISBNBK(), contracts.WBNB(), address(vault));
        }

        // approval rules
        if (block.chainid == 56) {
            address[] memory underlyingVaults = new address[](2);
            underlyingVaults[0] = contracts.YNWBNBK();
            underlyingVaults[1] = contracts.YNCLISBNBK();
            rules[i++] = BaseRules.getApprovalRule(contracts.WBNB(), underlyingVaults);
        } else if (block.chainid == 97) {
            rules[i++] = BaseRules.getApprovalRule(contracts.WBNB(), contracts.YNWBNBK());
        }

        // wbnb
        rules[i++] = BaseRules.getWethDepositRule(contracts.WBNB());
        rules[i++] = BaseRules.getWethWithdrawRule(contracts.WBNB());

        if (i != rulesLength) {
            revert InvalidRules();
        }

        SafeRules.setProcessorRules(vault, rules, false);

        vault.unpause();

        vault.processAccounting();

        BaseRoles.renounceTemporaryRoles(vault, deployer);
    }
}
