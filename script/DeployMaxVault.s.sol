// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {Provider, IProvider} from "src/module/Provider.sol";
import {IVault} from "src/interface/IVault.sol";

import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

import {
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FeeMath} from "src/module/FeeMath.sol";
import {BaseScript} from "script/BaseScript.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployMaxVault
contract DeployMaxVault is BaseScript {
    error InvalidRules();

    function symbol() public pure override returns (string memory) {
        return "ynRWAx";
    }

    function deployRateProvider() internal {
        if (block.chainid == 1) {
            rateProvider = IProvider(new Provider(address(wusdc)));
        }
    }

    function _verifySetup() public view override {
        super._verifySetup();
    }

    function run() public {
        deployer = msg.sender;

        vm.startBroadcast(deployer);

        _setup();
        _deployTimelockController();

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
        underlyingAssets[0] = contracts.USDC();
        maxVaultViewer.addUnderlyingAssets(underlyingAssets);

        maxVaultViewer.renounceRole(maxVaultViewer.DEFAULT_ADMIN_ROLE(), msg.sender);
        maxVaultViewer.renounceRole(maxVaultViewer.UPDATER_ROLE(), msg.sender);
    }

    function deploy() public {
        implementation = new Vault();

        address admin = msg.sender;

        console.log("Provisional admin:", admin);

        string memory name = "YieldNest RWA MAX";
        string memory symbol_ = "ynRWAx";
        uint8 decimals = 18;

        uint64 baseWithdrawalFee = uint64(0.001 ether * FeeMath.BASIS_POINT_SCALE / 1 ether); // 0.1%

        bool countNativeAsset = false;
        bool alwaysComputeTotalAssets = true;

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), "");

        vault = Vault(payable(address(proxy)));

        uint256 defaultAssetIndex = 1;
        vault.initialize(
            admin,
            name,
            symbol_,
            decimals,
            baseWithdrawalFee,
            countNativeAsset,
            alwaysComputeTotalAssets,
            defaultAssetIndex
        );

        wusdcImplementation = new WrappedToken();

        TransparentUpgradeableProxy wusdcProxy =
            new TransparentUpgradeableProxy(address(wusdcImplementation), address(timelock), "");

        wusdc = WrappedToken(payable(address(wusdcProxy)));

        deployRateProvider();

        wusdc.initialize(IERC20(contracts.USDC()), "Wrapped USDC", "WUSDC", 18, 12);

        configureVault();
    }

    function configureVault() internal {
        BaseRoles.configureDefaultRolesForMaxVault(vault, address(timelock), actors);
        BaseRoles.configureTemporaryRolesForMaxVault(vault, deployer);

        // set provider
        vault.setProvider(address(rateProvider));

        // add assets
        vault.addAsset(address(wusdc), false);
        vault.addAsset(contracts.USDC(), true);

        vault.unpause();

        vault.processAccounting();

        BaseRoles.renounceTemporaryRoles(vault, deployer);
    }
}
