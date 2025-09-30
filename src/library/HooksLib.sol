// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "src/interface/IHooks.sol";

library HooksLib {
    error HookCallFailed(bytes result);
    error InvalidPermission();

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
     * @param params The deposit parameters struct
     */
    function beforeDeposit(IHooks self, IHooks.DepositParams memory params) public {
        // checks if the hook is set and has the permission set for the beforeDeposit flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_DEPOSIT)) {
            callHook(self, abi.encodeCall(IHooks.beforeDeposit, (params)));
        }
    }

    /**
     * @notice Calls the afterDeposit hook if the hook is enabled
     * @param self The hooks contract
     * @param params The deposit parameters struct
     */
    function afterDeposit(IHooks self, IHooks.DepositParams memory params) public {
        // checks if the hook is set and has the permission set for the afterDeposit flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_DEPOSIT)) {
            callHook(self, abi.encodeCall(IHooks.afterDeposit, (params)));
        }
    }

    /**
     * @notice Calls the beforeMint hook if the hook is enabled
     * @param self The hooks contract
     * @param params The mint parameters struct
     */
    function beforeMint(IHooks self, IHooks.MintParams memory params) public {
        // checks if the hook is set and has the permission set for the beforeMint flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_MINT)) {
            callHook(self, abi.encodeCall(IHooks.beforeMint, (params)));
        }
    }

    /**
     * @notice Calls the afterMint hook if the hook is enabled
     * @param self The hooks contract
     * @param params The mint parameters struct
     */
    function afterMint(IHooks self, IHooks.MintParams memory params) public {
        // checks if the hook is set and has the permission set for the afterMint flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_MINT)) {
            callHook(self, abi.encodeCall(IHooks.afterMint, (params)));
        }
    }

    /**
     * @notice Calls the beforeRedeem hook if the hook has the permission set
     * @param self The hooks contract
     * @param params The redeem parameters struct
     */
    function beforeRedeem(IHooks self, IHooks.RedeemParams memory params) public {
        // checks if the hook is set and has the permission set for the beforeRedeem flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_REDEEM)) {
            callHook(self, abi.encodeCall(IHooks.beforeRedeem, (params)));
        }
    }

    /**
     * @notice Calls the afterRedeem hook if the hook has the permission set
     * @param self The hooks contract
     * @param params The redeem parameters struct
     */
    function afterRedeem(IHooks self, IHooks.RedeemParams memory params) public {
        // checks if the hook is set and has the permission set for the afterRedeem flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_REDEEM)) {
            callHook(self, abi.encodeCall(IHooks.afterRedeem, (params)));
        }
    }

    /**
     * @notice Calls the beforeWithdraw hook if the hook has the permission set
     * @param self The hooks contract
     * @param params The withdraw parameters struct
     */
    function beforeWithdraw(IHooks self, IHooks.WithdrawParams memory params) public {
        // checks if the hook is set and has the permission set for the beforeWithdraw flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_WITHDRAW)) {
            callHook(self, abi.encodeCall(IHooks.beforeWithdraw, (params)));
        }
    }

    /**
     * @notice Calls the afterWithdraw hook if the hook is enabled
     * @param self The hooks contract
     * @param params The withdraw parameters struct
     */
    function afterWithdraw(IHooks self, IHooks.WithdrawParams memory params) public {
        // checks if the hook is set and has the permission set for the afterWithdraw flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_WITHDRAW)) {
            callHook(self, abi.encodeCall(IHooks.afterWithdraw, (params)));
        }
    }

    /**
     * @notice Calls the beforeProcessAccounting hook if the hook is enabled
     * @param self The hooks contract
     * @param params The process accounting parameters struct
     */
    function beforeProcessAccounting(IHooks self, IHooks.BeforeProcessAccountingParams memory params) public {
        // checks if the hook is set and has the permission set for the beforeProcessAccounting flag
        if (address(self) != address(0) && hookEnabled(self, HookType.BEFORE_PROCESS_ACCOUNTING)) {
            callHook(self, abi.encodeCall(IHooks.beforeProcessAccounting, (params)));
        }
    }

    /**
     * @notice Calls the afterProcessAccounting hook if the hook is enabled
     * @param self The hooks contract
     * @param params The process accounting parameters struct
     */
    function afterProcessAccounting(IHooks self, IHooks.AfterProcessAccountingParams memory params) public {
        // checks if the hook is set and has the permission set for the afterProcessAccounting flag
        if (address(self) != address(0) && hookEnabled(self, HookType.AFTER_PROCESS_ACCOUNTING)) {
            callHook(self, abi.encodeCall(IHooks.afterProcessAccounting, (params)));
        }
    }
}
