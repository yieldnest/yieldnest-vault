// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IStrategy} from "src/interface/IStrategy.sol";
import {SafeERC20, IERC20} from "src/Common.sol";
import {BaseVault} from "src/BaseVault.sol";

contract Strategy is BaseVault {
    bytes32 public constant ALLOCATOR_ROLE = 0x68bf109b95a5c15fb2bb99041323c27d15f8675e11bf7420a1cd6ad64c394f46;

    /**
     * @notice Initializes the Strategy Vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     */
    function initialize(address admin, string memory name, string memory symbol) external initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _getVaultStorage().paused = true;
    }

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset convertion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal override onlyRole(ALLOCATOR_ROLE) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets += baseAssets;

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Internal function to handle withdrawals.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdraw(address asset_, address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        onlyRole(ALLOCATOR_ROLE)
    {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets -= assets;
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        IStrategy(vaultStorage.buffer).withdraw(assets, address(this), address(this));
        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
