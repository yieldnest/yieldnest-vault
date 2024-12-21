// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {Provider, IProvider} from "src/module/Provider.sol";
import {TestProvider} from "test/module/TestProvider.sol";

import {BaseVaultViewer} from "src/utils/BaseVaultViewer.sol";

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

    function run() public {
        vm.startBroadcast();

        _setup();
        _deployTimelockController();
        deployRateProvider();

        _verifySetup();

        deploy();

        BaseVaultViewer viewerImpl = new BaseVaultViewer();

        _deployViewer(address(viewerImpl));

        _saveDeployment();

        vm.stopBroadcast();
    }

    function deploy() internal {
        implementation = new Vault();

        address admin = msg.sender;
        // TODO: verify and confirm name of vault
        string memory name = "YieldNest BNB Max";
        string memory symbol_ = "ynBNBx";
        uint8 decimals = 18;

        uint64 baseWithdrawalFee = uint64(0.001 ether * FeeMath.BASIS_POINT_SCALE / 1 ether); // 0.1%

        bool countNativeAsset = true;
        bool alwaysComputeTotalAssets = true;

        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector,
            admin,
            name,
            symbol_,
            decimals,
            baseWithdrawalFee,
            countNativeAsset,
            alwaysComputeTotalAssets
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), initData);

        vault = Vault(payable(address(proxy)));

        configureVault();
    }

    function configureVault() internal {
        _configureDefaultRoles();
        _configureTemporaryRoles();

        // set provider
        vault.setProvider(address(rateProvider));

        // add assets
        vault.addAsset(contracts.WBNB(), true);
        vault.addAsset(contracts.SLISBNB(), true);
        vault.addAsset(contracts.BNBX(), true);

        // TODO: confirm if these values are correct
        if (contracts.YNWBNBK() != address(0x0b)) {
            vault.addAsset(contracts.YNWBNBK(), false);
        }
        vault.addAsset(contracts.YNBNBK(), true);
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
            setApprovalRule(vault, contracts.YNWBNBK(), contracts.WBNB());
        }

        // ynbnbk
        setDepositRule(vault, contracts.YNBNBK());
        setWithdrawRule(vault, contracts.YNBNBK());
        address[] memory assets = new address[](3);
        assets[0] = contracts.WBNB();
        assets[1] = contracts.SLISBNB();
        assets[2] = contracts.BNBX();
        setDepositAssetRule(vault, contracts.YNBNBK(), assets);
        setWithdrawAssetRule(vault, contracts.YNBNBK(), assets);
        setApprovalRule(vault, contracts.YNBNBK(), assets);

        // ynclisbnbk
        if (contracts.YNCLISBNBK() != address(0x0c)) {
            setDepositRule(vault, contracts.YNCLISBNBK());
            setWithdrawRule(vault, contracts.YNCLISBNBK());
            setDepositAssetRule(vault, contracts.YNCLISBNBK(), contracts.WBNB());
            setWithdrawAssetRule(vault, contracts.YNCLISBNBK(), contracts.WBNB());
            setApprovalRule(vault, contracts.YNCLISBNBK(), contracts.WBNB());
        }

        // wbnb
        setWethDepositRule(vault, contracts.WBNB());

        vault.unpause();

        vault.processAccounting();

        _renounceTemporaryRoles();
    }
}
