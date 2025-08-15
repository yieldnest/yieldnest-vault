// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "src/interface/IHooks.sol";

error HookCallFailed(bytes result);
error InvalidPermission();

library HooksLib {
    // @notice Flags for the hooks
    enum Flags {
        BEFORE_DEPOSIT,
        AFTER_DEPOSIT,
        BEFORE_MINT,
        AFTER_MINT,
        BEFORE_REDEEM,
        AFTER_REDEEM,
        BEFORE_WITHDRAW,
        AFTER_WITHDRAW,
        BEFORE_PROCESS_ACCOUNTING,
        AFTER_PROCESS_ACCOUNTING
    }

    // @notice Checks if the hook has the permission set for the given flag to be called
    // @param self The hooks contract
    // @param flag The flag to check
    // @return True if the hook has the permission, false otherwise
    function hasPermission(IHooks self, Flags flag) internal view returns (bool) {
        // gets the Permissions struct from the hooks contract
        IHooks.Permissions memory permissions = self.getPermissions();
        if (flag == Flags.BEFORE_DEPOSIT) return permissions.beforeDeposit;
        if (flag == Flags.AFTER_DEPOSIT) return permissions.afterDeposit;
        if (flag == Flags.BEFORE_MINT) return permissions.beforeMint;
        if (flag == Flags.AFTER_MINT) return permissions.afterMint;
        if (flag == Flags.BEFORE_REDEEM) return permissions.beforeRedeem;
        if (flag == Flags.AFTER_REDEEM) return permissions.afterRedeem;
        if (flag == Flags.BEFORE_WITHDRAW) return permissions.beforeWithdraw;
        if (flag == Flags.AFTER_WITHDRAW) return permissions.afterWithdraw;
        if (flag == Flags.BEFORE_PROCESS_ACCOUNTING) return permissions.beforeProcessAccounting;
        if (flag == Flags.AFTER_PROCESS_ACCOUNTING) return permissions.afterProcessAccounting;
        revert InvalidPermission();
    }

    // @notice Calls the hook with the given data
    // @param self The hooks contract
    // @param data The data to call the hook with
    // @return The result of the hook call
    function callHook(IHooks self, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory result) = address(self).call(data);
        if (!success) revert HookCallFailed(result);
        return result;
    }

    // @notice Calls the beforeDeposit hook if the hook has the permission set
    // @param self The hooks contract
    // @param assets The amount of assets to deposit
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param shares The amount of shares to be minted on deposit
    // @param baseAssets The amount of base assets to be deposited
    function beforeDeposit(
        IHooks self,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) internal {
        // checks if the hook is set and has the permission set for the beforeDeposit flag
        if (address(self) != address(0) && hasPermission(self, Flags.BEFORE_DEPOSIT)) {
            callHook(self, abi.encodeCall(IHooks.beforeDeposit, (assets, caller, receiver, shares, baseAssets)));
        }
    }

    // @notice Calls the afterDeposit hook if the hook has the permission set
    // @param self The hooks contract
    // @param assets The amount of assets to deposit
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param shares The amount of shares to be minted on deposit
    // @param baseAssets The amount of base assets to be deposited
    function afterDeposit(
        IHooks self,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) internal {
        // checks if the hook is set and has the permission set for the afterDeposit flag
        if (address(self) != address(0) && hasPermission(self, Flags.AFTER_DEPOSIT)) {
            callHook(self, abi.encodeCall(IHooks.afterDeposit, (assets, caller, receiver, shares, baseAssets)));
        }
    }

    // @notice Calls the beforeMint hook if the hook has the permission set
    // @dev For mint function, asset to be deposited will be base asset of vault
    // @param self The hooks contract
    // @param shares The amount of shares to be minted
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param assets The amount of assets to be deposited
    // @param baseAssets The amount of base assets to be deposited
    function beforeMint(
        IHooks self,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) internal {
        // checks if the hook is set and has the permission set for the beforeMint flag
        if (address(self) != address(0) && hasPermission(self, Flags.BEFORE_MINT)) {
            callHook(self, abi.encodeCall(IHooks.beforeMint, (shares, caller, receiver, assets, baseAssets)));
        }
    }

    // @notice Calls the afterMint hook if the hook has the permission set
    // @dev For mint function, asset to be deposited will be base asset of vault
    // @param self The hooks contract
    // @param shares The amount of shares to be minted
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param assets The amount of assets to be deposited
    // @param baseAssets The amount of base assets to be deposited
    function afterMint(
        IHooks self,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) internal {
        // checks if the hook is set and has the permission set for the afterMint flag
        if (address(self) != address(0) && hasPermission(self, Flags.AFTER_MINT)) {
            callHook(self, abi.encodeCall(IHooks.afterMint, (shares, caller, receiver, assets, baseAssets)));
        }
    }

    // @notice Calls the beforeRedeem hook if the hook has the permission set
    // @param self The hooks contract
    // @param shares The amount of shares to be redeemed
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param owner The address of the owner of the shares
    // @param assets The amount of assets to be redeemed
    // @param baseAssets The amount of base assets to be redeemed
    function beforeRedeem(IHooks self, uint256 shares, address caller, address receiver, address owner, uint256 assets)
        internal
    {
        // checks if the hook is set and has the permission set for the beforeRedeem flag
        if (address(self) != address(0) && hasPermission(self, Flags.BEFORE_REDEEM)) {
            callHook(self, abi.encodeCall(IHooks.beforeRedeem, (shares, caller, receiver, owner, assets)));
        }
    }

    // @notice Calls the afterRedeem hook if the hook has the permission set
    // @param self The hooks contract
    // @param shares The amount of shares to be redeemed
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param owner The address of the owner of the shares
    // @param assets The amount of assets to be redeemed
    // @param baseAssets The amount of base assets to be redeemed
    function afterRedeem(IHooks self, uint256 shares, address caller, address receiver, address owner, uint256 assets)
        internal
    {
        // checks if the hook is set and has the permission set for the afterRedeem flag
        if (address(self) != address(0) && hasPermission(self, Flags.AFTER_REDEEM)) {
            callHook(self, abi.encodeCall(IHooks.afterRedeem, (shares, caller, receiver, owner, assets)));
        }
    }

    // @notice Calls the beforeWithdraw hook if the hook has the permission set
    // @param self The hooks contract
    // @param assets The amount of assets to withdraw
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param owner The address of the owner of the shares
    // @param shares The amount of shares to be burned on withdraw
    function beforeWithdraw(
        IHooks self,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) internal {
        // checks if the hook is set and has the permission set for the beforeWithdraw flag
        if (address(self) != address(0) && hasPermission(self, Flags.BEFORE_WITHDRAW)) {
            callHook(self, abi.encodeCall(IHooks.beforeWithdraw, (assets, caller, receiver, owner, shares)));
        }
    }

    // @notice Calls the afterWithdraw hook if the hook has the permission set
    // @param self The hooks contract
    // @param assets The amount of assets to withdraw
    // @param caller The address of the caller
    // @param receiver The address of the receiver of shares
    // @param owner The address of the owner of the shares
    // @param shares The amount of shares to be burned on withdraw
    function afterWithdraw(IHooks self, uint256 assets, address caller, address receiver, address owner, uint256 shares)
        internal
    {
        // checks if the hook is set and has the permission set for the afterWithdraw flag
        if (address(self) != address(0) && hasPermission(self, Flags.AFTER_WITHDRAW)) {
            callHook(self, abi.encodeCall(IHooks.afterWithdraw, (assets, caller, receiver, owner, shares)));
        }
    }

    // @notice Calls the beforeProcessAccounting hook if the hook has the permission set
    // @param self The hooks contract
    // @param totalAssetsBeforeAccounting The total assets before accounting
    // @param totalSupplyBeforeAccounting The total supply before accounting
    // @param totalBaseBalanceBeforeAccounting The total base balance before accounting
    function beforeProcessAccounting(
        IHooks self,
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) internal {
        // checks if the hook is set and has the permission set for the beforeProcessAccounting flag
        if (address(self) != address(0) && hasPermission(self, Flags.BEFORE_PROCESS_ACCOUNTING)) {
            callHook(
                self,
                abi.encodeCall(
                    IHooks.beforeProcessAccounting,
                    (totalAssetsBeforeAccounting, totalSupplyBeforeAccounting, totalBaseBalanceBeforeAccounting)
                )
            );
        }
    }

    // @notice Calls the afterProcessAccounting hook if the hook has the permission set
    // @param self The hooks contract
    // @param totalAssetsBeforeAccounting The total assets before accounting
    // @param totalAssetsAfterAccounting The total assets after accounting
    // @param totalSupplyBeforeAccounting The total supply before accounting
    // @param totalSupplyAfterAccounting The total supply after accounting
    // @param totalBaseBalanceAfterAccounting The total base balance after accounting
    // @param totalBaseBalanceBeforeAccounting The total base balance before accounting
    function afterProcessAccounting(
        IHooks self,
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseBalanceAfterAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) internal {
        // checks if the hook is set and has the permission set for the afterProcessAccounting flag
        if (address(self) != address(0) && hasPermission(self, Flags.AFTER_PROCESS_ACCOUNTING)) {
            callHook(
                self,
                abi.encodeCall(
                    IHooks.afterProcessAccounting,
                    (
                        totalAssetsBeforeAccounting,
                        totalAssetsAfterAccounting,
                        totalSupplyBeforeAccounting,
                        totalSupplyAfterAccounting,
                        totalBaseBalanceAfterAccounting,
                        totalBaseBalanceBeforeAccounting
                    )
                )
            );
        }
    }
}
