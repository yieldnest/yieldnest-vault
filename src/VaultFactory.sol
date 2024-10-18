// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AccessControlUpgradeable, TransparentUpgradeableProxy, IERC20, IERC4626} from "src/Common.sol";

import {IVaultFactory} from "src/interface/IVaultFactory.sol";
import {IWETH} from "src/interface/IWETH.sol";

contract VaultFactory is IVaultFactory, AccessControlUpgradeable {
    /// @dev This timelock is the Vault Proxy Admin.
    address public timelock;

    /// @dev The address of the SingleVault implementation contract.
    address public singleVaultImpl;

    IWETH public weth;

    event NewVault(address indexed vault, string name, string symbol, VaultType vaultType);
    event SetVersion(address indexed implementation, VaultType vaultType);
    event WethReturned(address receiver, uint256 amount);

    error ZeroAddress();
    error InvalidWethAddress();

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the VaultFactory contract.
     * @param singleVaultImpl_ The address of the SingleVault implementation contract.
     * @param admin The address of the administrator.
     * @param timelock_ The Vault admin for proxy upgrades
     */
    function initialize(address singleVaultImpl_, address admin, address timelock_, address weth_) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // NOTES: There are two timelocks. This timelock is for vault upgrades but
        // the vault is the second timelock controller, which has the same proposers and executors
        // as the proxy admins
        singleVaultImpl = singleVaultImpl_;
        timelock = timelock_;
        weth = IWETH(payable(weth_));
    }

    /**
     * @dev Creates a new SingleVault instance and deploys it behind a proxy.
     * @param asset_ The ERC20 asset to be used by the vault.
     * @param name_ The name of the vault.
     * @param symbol_ The symbol of the vault.
     * @param admin_ The address of the timelock.
     * @return address The address of the newly created vault.
     */
    function createSingleVault(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        string memory funcSig = "initialize(address,string,string,address)";

        if (address(asset_) != address(weth)) revert InvalidWethAddress();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            singleVaultImpl,
            timelock,
            abi.encodeWithSignature(funcSig, asset_, name_, symbol_, admin_)
        );

        // bootstrap 1 ether of weth to prevent donation attacks
        IERC20(asset_).approve(address(proxy), 1 ether);
        IERC4626(address(proxy)).deposit(1 ether, admin_);
        emit NewVault(address(proxy), name_, symbol_, VaultType.SingleAsset);
        return address(proxy);
    }

    /**
     * @dev Returns the WETH that was deposited to the factory.
     * @param receiver The address to receiver the boostrapped weth.
     */
    function getDepositedWETH(address receiver) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = IERC20(weth).balanceOf(address(this));
        IERC20(weth).approve(receiver, balance);
        IERC20(weth).transfer(receiver, balance);
        emit WethReturned(receiver, balance);
    }
}
