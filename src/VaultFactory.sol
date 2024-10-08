// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AccessControlUpgradeable, TransparentUpgradeableProxy, IERC20, IERC4626} from "src/Common.sol";

import {IVaultFactory} from "src/IVaultFactory.sol";

contract VaultFactory is IVaultFactory, AccessControlUpgradeable {
    /// @dev This timelock is the Vault Proxy Admin.
    address public timelock;

    /// @dev The address of the SingleVault implementation contract.
    address public singleVaultImpl;

    /// @dev The address of the MultiVault implementation contract.
    address public multiVaultImpl;

    /// @dev Mapping of vault addresses to their respective Vault structs.
    mapping(address => Vault) public vaults;

    event NewVault(address indexed vault, string name, string symbol, VaultType vaultType);
    event SetVersion(address indexed implementation, VaultType vaultType);

    error ZeroAddress();

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the VaultFactory contract.
     * @param singleVaultImpl_ The address of the SingleVault implementation contract.
     * @param admin The address of the administrator.
     * @param timelock_ The Vault admin for proxy upgrades
     */
    function initialize(address singleVaultImpl_, address admin, address timelock_) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // NOTES: There are two timelocks. This timelock is for vault upgrades but
        // the vault is the second timelock controller, which has the same proposers and executors
        // as the proxy admins
        singleVaultImpl = singleVaultImpl_;
        timelock = timelock_;
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
        string memory funcSig = "initialize(address,string,string,address,uint256,address[],address[])";

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            singleVaultImpl,
            timelock,
            abi.encodeWithSignature(funcSig, asset_, name_, symbol_, admin_, minDelay_, proposers_, executors_)
        );
        vaults[address(proxy)] = Vault(address(timelock), name_, symbol_, VaultType.SingleAsset);

        // bootstrap 1 ether of underlying to prevent donation attacks
        IERC20(asset_).approve(address(proxy), 1 ether);
        IERC4626(address(proxy)).deposit(1 ether, admin_);
        emit NewVault(address(proxy), name_, symbol_, VaultType.SingleAsset);
        return address(proxy);
    }

    function createMetaVault(
        IERC20[] assets_,
        string memory name_,
        string memory symbol_,
        address memory admin_,
        uint256 minDelay_,
        address[] memory proposers_,
        address[] memory executors_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        string memory funcSig = "initialize(address,string,string,address,uint256,address[],address[])";

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            singleVaultImpl,
            timelock,
            abi.encodeWithSignature(funcSig, assets_, name_, symbol_, admin_, minDelay_, proposers_, executors_)
        );
        vaults[address(proxy)] = Vault(address(timelock), name_, symbol_, VaultType.SingleAsset);

        // bootstrap 1 ether of underlying to prevent donation attacks
        IERC20(asset_).approve(address(proxy), 1 ether);
        IERC4626(address(proxy)).deposit(1 ether, admin_);
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
