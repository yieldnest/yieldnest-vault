// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {TimelockController, TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHxVault} from "src/YnETHxVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {Provider} from "src/module/Provider.sol";
import {YieldNestRules} from "script/rules/YieldNestRules.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";

contract YnETHxConfigurer is BaseRules, ConnectorRules, YieldNestRules, WithdrawerRules, MainnetActors {
    error NotAdmin();
    error InvalidVaultVersion();

    event TimelockDeployed(address timelock);
    event ProviderDeployed(address provider);
    event WithdrawerDeployed(address withdrawer);
    event VaultConfigured(address vault);

    function _deployTimelockController() internal virtual returns (address) {
        uint256 minDelay = 1 days;

        address[] memory proposers = new address[](1);
        proposers[0] = PROPOSER_1;

        address[] memory executors = new address[](1);
        executors[0] = EXECUTOR_1;

        TimelockController timelock = new TimelockController(minDelay, proposers, executors, ADMIN);
        emit TimelockDeployed(address(timelock));
        return address(timelock);
    }

    function _configureDefaultRoles(BaseVault vault, address timelock) internal virtual {
        // set admin roles
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN);
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // set timelock roles
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), timelock);
    }

    function _configureTemporaryRoles(BaseVault vault) internal virtual {
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.UNPAUSER_ROLE(), address(this));
    }

    function _renounceTemporaryRoles(BaseVault vault) internal virtual {
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
        vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.UNPAUSER_ROLE(), address(this));
    }

    function _deployWithdrawer(address provider) internal returns (address) {
        Withdrawer vaultImplementation = new Withdrawer();

        // Deploy the proxy
        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, "");

        Withdrawer vault = Withdrawer(payable(address(vaultProxy)));

        {
            // initialize
            string memory name = "YieldNest Withdrawer";
            string memory symbol = "ynWithdrawer";
            uint8 decimals_ = 18;
            bool countNativeAsset_ = true;
            bool alwaysComputeTotalAssets_ = false;

            vault.initialize(address(this), name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
        }

        {
            // configure roles
            address timelock = _deployTimelockController();
            _configureDefaultRoles(vault, timelock);
            _configureTemporaryRoles(vault);
            vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
            vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        {
            // add assets: Base asset always first
            vault.addAsset(MC.WETH, true, true);
            vault.addAsset(MC.STETH, true, false);
            vault.addAsset(MC.WSTETH, true, false);
            vault.addAsset(MC.METH, true, false);
            vault.addAsset(MC.RETH, true, false);
            vault.addAsset(MC.WOETH, true, false);
            vault.addAsset(MC.OETH, true, false);
            vault.addAsset(MC.SWELL, true, false);
            vault.addAsset(MC.SFRXETH, true, false);
            vault.addAsset(MC.YNLSDE, true, false);
            vault.addAsset(MC.YNETH, true, false);
        }

        {
            // ynETH withdrawal queue
            setApprovalRule(vault, MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            setRequestWithdrawalRule(vault, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            setClaimWithdrawalRule(vault, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
        }

        {
            // ynLSDe withdrawal queue
            setApprovalRule(vault, MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            setRequestWithdrawalRule(vault, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            setClaimWithdrawalRule(vault, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
        }

        {
            // wstETH withdrawal queue
            setApprovalRule(vault, MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE);
            setRequestWithdrawalWstETHRule(vault, MC.WSTETH_WITHDRAWAL_QUEUE);
            setClaimWithdrawalWstETHRule(vault, MC.WSTETH_WITHDRAWAL_QUEUE);
        }

        // NOTE: woeth withdrawal is handled via direct methods on the vault

        // TODO: add rules for wrap/unwrap WSTETH and WOETH

        vault.unpause();

        _renounceTemporaryRoles(vault);

        return address(vault);
    }

    function configure() external {
        YnETHxVault vault = YnETHxVault(payable(MC.YNETHX));
        if (!vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(this))) {
            revert NotAdmin();
        }
        if (keccak256(bytes(vault.VAULT_VERSION())) != keccak256(bytes("0.2.0"))) {
            revert InvalidVaultVersion();
        }

        address provider = address(new Provider());
        emit ProviderDeployed(provider);

        address withdrawer = _deployWithdrawer(provider);
        emit WithdrawerDeployed(withdrawer);

        {
            // configure roles
            _configureDefaultRoles(vault, MC.TIMELOCK);
            vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);
            _configureTemporaryRoles(vault);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        // set the buffer
        vault.setBuffer(MC.EULER_WETH_22_VAULT);

        {
            // add assets: Base asset always first
            vault.addAsset(MC.WETH, true);
            vault.addAsset(MC.YNETH, true);
            vault.addAsset(MC.YNLSDE, true);

            vault.addAsset(MC.EULER_WETH_22_VAULT, false); // buffer
            vault.addAsset(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, false);
            vault.addAsset(MC.STETH, false);
            vault.addAsset(MC.WSTETH, false);
            vault.addAsset(MC.OETH, false);
            vault.addAsset(MC.WOETH, false);
            vault.addAsset(withdrawer, false);
        }

        {
            // wrap/unwrap ETH
            setWethDepositRule(vault, MC.WETH);
            setWethWithdrawRule(vault, MC.WETH);
        }

        {
            // approvals for WETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.EULER_WETH_22_VAULT;
            strategies[1] = withdrawer;
            setApprovalRule(vault, MC.WETH, strategies);
        }

        {
            // approvals for wstETH and woETH
            address[] memory assets = new address[](2);
            assets[0] = MC.WSTETH;
            assets[1] = MC.WOETH;

            address[] memory strategies = new address[](2);
            strategies[0] = MC.YNLSDE;
            strategies[1] = withdrawer;

            for (uint256 i = 0; i < assets.length; i++) {
                setApprovalRule(vault, assets[i], strategies);
            }
        }

        {
            // buffer deposit/withdraw WETH
            // setApprovalRule(vault, MC.WETH, MC.EULER_WETH_22_VAULT);
            setDepositRule(vault, MC.EULER_WETH_22_VAULT);
            setWithdrawRule(vault, MC.EULER_WETH_22_VAULT);
        }

        {
            // depositETH on ynETH
            setYnETHDepositRule(vault, MC.YNETH, address(vault));
        }

        {
            // deposit(asset, amount, receiver) for wstETH and woETH to ynLSDe
            address[] memory assets = new address[](2);
            assets[0] = MC.WSTETH;
            assets[1] = MC.WOETH;
            // for (uint256 i = 0; i < assets.length; i++) {
            //     setApprovalRule(vault, assets[i], MC.YNLSDE);
            // }
            setYnEigenDepositRule(vault, MC.YNLSDE, assets, address(vault));
        }

        {
            // approvals for ynETH and ynLSDe
            address[] memory assets = new address[](2);
            assets[0] = MC.YNETH;
            assets[1] = MC.YNLSDE;

            address[] memory strategies = new address[](2);
            strategies[0] = MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR;
            strategies[1] = withdrawer;

            for (uint256 i = 0; i < assets.length; i++) {
                setApprovalRule(vault, assets[i], strategies);
            }
        }

        {
            // ynETH-ynLSDe pool connector & tokenized strategy
            // setApprovalRule(vault, MC.YNETH, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            // setApprovalRule(vault, MC.YNLSDE, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            setConnectorDepositRule(vault, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            setConnectorWithdrawRule(vault, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
        }

        {
            // withdrawer deposit all assets and withdraw WETH
            address[] memory assets = new address[](10);
            uint256 index = 0;

            assets[index++] = MC.WETH;
            assets[index++] = MC.YNETH;
            assets[index++] = MC.YNLSDE;
            assets[index++] = MC.WOETH;
            assets[index++] = MC.OETH;
            assets[index++] = MC.WSTETH;
            assets[index++] = MC.STETH;
            assets[index++] = MC.METH;
            assets[index++] = MC.SFRXETH;

            for (uint256 i = 0; i < assets.length; i++) {
                if (
                    assets[i] == MC.WETH || assets[i] == MC.WSTETH || assets[i] == MC.WOETH || assets[i] == MC.YNETH
                        || assets[i] == MC.YNLSDE
                ) {
                    continue;
                }
                setApprovalRule(vault, assets[i], withdrawer);
            }
            setDepositAssetRule(vault, withdrawer, assets);

            // Withdrawable: only WETH
            setWithdrawRule(vault, withdrawer);
            setWithdrawAssetRule(vault, withdrawer, MC.WETH);
        }

        vault.unpause();

        _renounceTemporaryRoles(vault);
        emit VaultConfigured(address(vault));
    }
}
