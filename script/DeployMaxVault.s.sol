// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {Provider, IProvider} from "src/module/Provider.sol";
import {TestProvider} from "test/module/TestProvider.sol";

import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FeeMath} from "src/module/FeeMath.sol";
import {BaseScript} from "script/BaseScript.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployMaxVault
contract DeployMaxVault is BaseScript {
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
        maxVaultViewer.renounceRole(maxVaultViewer.DEFAULT_ADMIN_ROLE(), msg.sender);
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
        _configureDefaultRoles();
        _configureTemporaryRoles();

        bool isEnabledYnBNBk = false;

        // set provider
        vault.setProvider(address(rateProvider));

        // add assets
        vault.addAsset(contracts.WBNB(), true);
        if (isEnabledYnBNBk) {
            vault.addAsset(contracts.SLISBNB(), true);
            vault.addAsset(contracts.BNBX(), true);
        }

        // TODO: confirm if these values are correct
        if (contracts.YNWBNBK() != address(0x0b)) {
            vault.addAsset(contracts.YNWBNBK(), false);
        }
        if (isEnabledYnBNBk) {
            vault.addAsset(contracts.YNBNBK(), true);
        }
        if (contracts.YNCLISBNBK() != address(0x0c)) {
            vault.addAsset(contracts.YNCLISBNBK(), false);
        }

        // buffer or ynwbnbk
        if (contracts.YNWBNBK() != address(0x0b)) {
            vault.setBuffer(contracts.YNWBNBK());

            setDepositRule(vault, contracts.YNWBNBK());
            setWithdrawRule(vault, contracts.YNWBNBK());
            setDepositAssetRule(vault, contracts.YNWBNBK(), contracts.WBNB());
            setWithdrawAssetRule(vault, contracts.YNWBNBK(), contracts.WBNB());
        }

        // ynbnbk
        if (isEnabledYnBNBk) {
            setDepositRule(vault, contracts.YNBNBK());
            setWithdrawRule(vault, contracts.YNBNBK());
            address[] memory assets = new address[](3);
            assets[0] = contracts.WBNB();
            assets[1] = contracts.SLISBNB();
            assets[2] = contracts.BNBX();
            setDepositAssetRule(vault, contracts.YNBNBK(), assets);
            setWithdrawAssetRule(vault, contracts.YNBNBK(), assets);
            // TODO: fix approval rule for ynbnbk
        }

        // ynclisbnbk
        if (contracts.YNCLISBNBK() != address(0x0c)) {
            setDepositRule(vault, contracts.YNCLISBNBK());
            setWithdrawRule(vault, contracts.YNCLISBNBK());
            setDepositAssetRule(vault, contracts.YNCLISBNBK(), contracts.WBNB());
            setWithdrawAssetRule(vault, contracts.YNCLISBNBK(), contracts.WBNB());
        }

        // approval rules
        if (block.chainid == 56) {
            address[] memory underlyingVaults = new address[](2);
            underlyingVaults[0] = contracts.YNWBNBK();
            underlyingVaults[1] = contracts.YNCLISBNBK();
            setApprovalRule(vault, contracts.WBNB(), underlyingVaults);
        } else if (block.chainid == 97) {
            setApprovalRule(vault, contracts.WBNB(), contracts.YNWBNBK());
        }

        // wbnb
        setWethDepositRule(vault, contracts.WBNB());
        setWethWithdrawRule(vault, contracts.WBNB());

        vault.unpause();

        vault.processAccounting();

        _renounceTemporaryRoles();
    }
}
