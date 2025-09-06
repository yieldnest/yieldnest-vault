// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "src/interface/IHooks.sol";

error HookCallFailed(bytes result);
error InvalidPermission();

library HooksLib {
    /// @notice Flags for the hooks
    enum HookType {
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

    /**
     * @notice Checks if the hook has the permission set for the given flag to be called
     * @param self The hooks contract
     * @param hookType The hook type to check
     * @return True if the hook has the permission, false otherwise
     */
    function hookEnabled(IHooks self, HookType hookType) internal view returns (bool) {
        // gets the config struct from the hooks contract
        IHooks.Config memory config = self.getConfig();
        if (hookType == HookType.BEFORE_DEPOSIT) return config.beforeDeposit;
        if (hookType == HookType.AFTER_DEPOSIT) return config.afterDeposit;
        if (hookType == HookType.BEFORE_MINT) return config.beforeMint;
        if (hookType == HookType.AFTER_MINT) return config.afterMint;
        if (hookType == HookType.BEFORE_REDEEM) return config.beforeRedeem;
        if (hookType == HookType.AFTER_REDEEM) return config.afterRedeem;
        if (hookType == HookType.BEFORE_WITHDRAW) return config.beforeWithdraw;
        if (hookType == HookType.AFTER_WITHDRAW) return config.afterWithdraw;
        if (hookType == HookType.BEFORE_PROCESS_ACCOUNTING) return config.beforeProcessAccounting;
        if (hookType == HookType.AFTER_PROCESS_ACCOUNTING) return config.afterProcessAccounting;
        revert InvalidPermission();
    }

    /**
     * @notice Calls the hook with the given data
     * @param self The hooks contract
     * @param data The data to call the hook with
     * @return The result of the hook call
     */
    function callHook(IHooks self, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory result) = address(self).call(data);
        if (!success) revert HookCallFailed(result);
        return result;
    }

    /**
     * @notice Calls the beforeDeposit hook if the hook is enabled
     * @param self The hooks contract
     * @param asset The address of the asset to deposit
     * @param assets The amount of assets to deposit
     * @param caller The address of the caller
     * @param receiver The address of the receiver of shares
     * @param shares The amount of shares to be minted on deposit
     * @param baseAssets The amount of base assets to be deposited
     */
    function beforeDeposit(
        IHooks self,
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) public {
        // checks if the hook is set and has the permission set for the beforeDeposit flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_DEPOSIT)) {
            callHook(self, abi.encodeCall(IHooks.beforeDeposit, (asset, assets, caller, receiver, shares, baseAssets)));
        }
    }
    /**
     * @notice Calls the afterDeposit hook if the hook is enabled
     * @param self The hooks contract
     * @param asset The address of the asset to deposit
     * @param assets The amount of assets to deposit
     * @param caller The address of the caller
     * @param receiver The address of the receiver of shares
     * @param shares The amount of shares to be minted on deposit
     * @param baseAssets The amount of base assets to be deposited
     */

    function afterDeposit(
        IHooks self,
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) public {
        // checks if the hook is set and has the permission set for the afterDeposit flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_DEPOSIT)) {
            callHook(self, abi.encodeCall(IHooks.afterDeposit, (asset, assets, caller, receiver, shares, baseAssets)));
        }
    }

    /**
     * @notice Calls the beforeMint hook if the hook is enabled
     * @dev For mint function, asset to be deposited will be base asset of vault
     * @param self The hooks contract
     * @param asset The address of the asset to deposit
     * @param shares The amount of shares to be minted
     * @param caller The address of the caller
     * @param receiver The address of the receiver of shares
     * @param assets The amount of assets to be deposited
     * @param baseAssets The amount of base assets to be deposited
     */
    function beforeMint(
        IHooks self,
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) public {
        // checks if the hook is set and has the permission set for the beforeMint flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_MINT)) {
            callHook(self, abi.encodeCall(IHooks.beforeMint, (asset, shares, caller, receiver, assets, baseAssets)));
        }
    }

    /**
     * @notice Calls the afterMint hook if the hook is enabled
     * @dev For mint function, asset to be deposited will be base asset of vault
     * @param self The hooks contract
     * @param asset The address of the asset to deposit
     * @param shares The amount of shares to be minted
     * @param caller The address of the caller
     * @param receiver The address of the receiver of shares
     * @param assets The amount of assets to be deposited
     * @param baseAssets The amount of base assets to be deposited
     */
    function afterMint(
        IHooks self,
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) public {
        // checks if the hook is set and has the permission set for the afterMint flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_MINT)) {
            callHook(self, abi.encodeCall(IHooks.afterMint, (asset, shares, caller, receiver, assets, baseAssets)));
        }
    }

    /**
     * @notice Calls the beforeRedeem hook if the hook has the permission set
     * @param self The hooks contract
     * @param asset The address of the asset to redeem
     * @param shares The amount of shares to be redeemed
     * @param caller The address of the caller
     * @param receiver The address of the receiver of assets
     * @param owner The address of the owner of the shares
     * @param assets The amount of assets to be redeemed
     */
    function beforeRedeem(
        IHooks self,
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) public {
        // checks if the hook is set and has the permission set for the beforeRedeem flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_REDEEM)) {
            callHook(self, abi.encodeCall(IHooks.beforeRedeem, (asset, shares, caller, receiver, owner, assets)));
        }
    }

    /**
     * @notice Calls the afterRedeem hook if the hook has the permission set
     * @param self The hooks contract
     * @param asset The address of the asset that was redeemed
     * @param shares The amount of shares that were redeemed
     * @param caller The address of the caller
     * @param receiver The address of the receiver of assets
     * @param owner The address of the owner of the shares
     * @param assets The amount of assets that were redeemed
     */
    function afterRedeem(
        IHooks self,
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) public {
        // checks if the hook is set and has the permission set for the afterRedeem flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_REDEEM)) {
            callHook(self, abi.encodeCall(IHooks.afterRedeem, (asset, shares, caller, receiver, owner, assets)));
        }
    }

    /**
     * @notice Calls the beforeWithdraw hook if the hook has the permission set
     * @param self The hooks contract
     * @param asset The address of the asset to withdraw
     * @param assets The amount of assets to withdraw
     * @param caller The address of the caller
     * @param receiver The address of the receiver of assets
     * @param owner The address of the owner of the shares
     * @param shares The amount of shares to be burned on withdraw
     */
    function beforeWithdraw(
        IHooks self,
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) public {
        // checks if the hook is set and has the permission set for the beforeWithdraw flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_WITHDRAW)) {
            callHook(self, abi.encodeCall(IHooks.beforeWithdraw, (asset, assets, caller, receiver, owner, shares)));
        }
    }

    /**
     * @notice Calls the afterWithdraw hook if the hook is enabled
     * @param self The hooks contract
     * @param asset The address of the asset that was withdrawn
     * @param assets The amount of assets that were withdrawn
     * @param caller The address of the caller
     * @param receiver The address of the receiver of assets
     * @param owner The address of the owner of the shares
     * @param shares The amount of shares that were burned on withdraw
     */
    function afterWithdraw(
        IHooks self,
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) public {
        // checks if the hook is set and has the permission set for the afterWithdraw flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_WITHDRAW)) {
            callHook(self, abi.encodeCall(IHooks.afterWithdraw, (asset, assets, caller, receiver, owner, shares)));
        }
    }

    /**
     * @notice Calls the beforeProcessAccounting hook if the hook is enabled
     * @param self The hooks contract
     * @param totalAssetsBeforeAccounting The total assets before accounting
     * @param totalSupplyBeforeAccounting The total supply before accounting
     * @param totalBaseAssetsBeforeAccounting The total base assets before accounting
     */
    function beforeProcessAccounting(
        IHooks self,
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseAssetsBeforeAccounting
    ) public {
        // checks if the hook is set and has the permission set for the beforeProcessAccounting flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_PROCESS_ACCOUNTING)) {
            callHook(
                self,
                abi.encodeCall(
                    IHooks.beforeProcessAccounting,
                    (totalAssetsBeforeAccounting, totalSupplyBeforeAccounting, totalBaseAssetsBeforeAccounting)
                )
            );
        }
    }

    /**
     * @notice Calls the afterProcessAccounting hook if the hook is enabled
     * @param self The hooks contract
     * @param totalAssetsBeforeAccounting The total assets before accounting
     * @param totalAssetsAfterAccounting The total assets after accounting
     * @param totalSupplyBeforeAccounting The total supply before accounting
     * @param totalSupplyAfterAccounting The total supply after accounting
     * @param totalBaseAssetsAfterAccounting The total base assets after accounting
     * @param totalBaseAssetsBeforeAccounting The total base assets before accounting
     */
    function afterProcessAccounting(
        IHooks self,
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseAssetsAfterAccounting,
        uint256 totalBaseAssetsBeforeAccounting
    ) public {
        // checks if the hook is set and has the permission set for the afterProcessAccounting flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_PROCESS_ACCOUNTING)) {
            callHook(
                self,
                abi.encodeCall(
                    IHooks.afterProcessAccounting,
                    (
                        totalAssetsBeforeAccounting,
                        totalAssetsAfterAccounting,
                        totalSupplyBeforeAccounting,
                        totalSupplyAfterAccounting,
                        totalBaseAssetsAfterAccounting,
                        totalBaseAssetsBeforeAccounting
                    )
                )
            );
        }
    }
}
