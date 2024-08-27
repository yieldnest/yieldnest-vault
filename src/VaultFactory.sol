// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    AccessControlUpgradeable,
    TransparentUpgradeableProxy,
    TimelockController,
    ProxyAdmin,
    IERC20
} from "src/Common.sol";

contract VaultFactory is AccessControlUpgradeable {
    string public constant version = "0.1.0";

    TimelockController public timelock;

    address public singleVaultImpl;
    address public multiVaultImpl;

    struct Vault {
        address vault;
        address timelock;
        string name;
        string symbol;
        VaultType vaultType;
    }

    enum VaultType {
        SingleAsset,
        MultiAsset
    }

    mapping(string => Vault) public vaults;

    event NewVault(address indexed vault, string name, string symbol, VaultType vaultType);
    event SetVersion(address indexed implementation, VaultType vaultType);

    error SymbolUsed();
    error ZeroAddress();

    /**
     * @dev Initializes the VaultFactory contract.
     * @param singleVaultImpl_ The address of the SingleVault implementation contract.
     * @param proposers Array of addresses that can propose transactions.
     * @param executors Array of addresses that can execute transactions.
     * @param minDelay The minimum delay in seconds before a proposed transaction can be executed.
     * @param admin The address of the administrator.
     */
    constructor(
        address singleVaultImpl_,
        address[] memory proposers,
        address[] memory executors,
        uint256 minDelay,
        address admin
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // NOTES: There are two timelocks. This timelock is for vault upgrades but
        // the vault is the second timelock controller, which has the same proposers and executors
        // as the proxy admins
        timelock = new TimelockController(minDelay, proposers, executors, admin);
        singleVaultImpl = singleVaultImpl_;
    }

    /**
     * @dev Creates a new SingleVault instance and deploys it behind a proxy.
     * @param asset_ The ERC20 asset to be used by the vault.
     * @param name_ The name of the vault.
     * @param symbol_ The symbol of the vault.
     * @param admin_ The address of the admin.
     * @param minDelay_ The timelock delay for transactions.
     * @param proposers_ Array of transaction proposers.
     * @param executors_ Array of transaction executors.
     * @return address The address of the newly created vault.
     */
    function createSingleVault(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        uint256 minDelay_,
        address[] memory proposers_,
        address[] memory executors_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        if (vaults[symbol_].vault != address(0)) revert SymbolUsed();

        string memory funcSig = "initialize(address,string,string,address,uint256,address[],address[])";

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            singleVaultImpl,
            address(timelock),
            abi.encodeWithSignature(
                funcSig, asset_, name_, symbol_, admin_, minDelay_, proposers_, executors_
            )
        );
        vaults[symbol_] = Vault(address(proxy), address(timelock), name_, symbol_, VaultType.SingleAsset);
        emit NewVault(address(proxy), name_, symbol_, VaultType.SingleAsset);
        return address(proxy);
    }

    /**
     * @dev Sets the SingleVault implementation contract address.
     * @param implementation_ The address of the SingleVault implementation contract.
     * @param vaultType Enum VaultType
     */
    function setVaultVersion(address implementation_, VaultType vaultType) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (implementation_ == address(0)) revert ZeroAddress();
        vaultType == VaultType.SingleAsset ? singleVaultImpl = implementation_ : multiVaultImpl = implementation_;
        emit SetVersion(implementation_, vaultType);
    }
}
