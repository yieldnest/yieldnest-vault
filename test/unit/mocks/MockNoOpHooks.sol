// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IHooks} from "src/interface/IHooks.sol";
import {IVault} from "src/interface/IVault.sol";

contract MockNoOpHooks is IHooks {
    IVault public immutable VAULT;
    Config private _config;

    constructor(IVault vault_) {
        VAULT = vault_;
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) {
            revert CallerNotVault();
        }
        _;
    }

    function setConfig(Config memory config_) external override {
        _config = config_;
    }

    function getConfig() external view override returns (Config memory) {
        return _config;
    }

    function beforeDeposit(DepositParams memory /* params */ ) external override onlyVault {}

    function afterDeposit(DepositParams memory /* params */ ) external override onlyVault {}

    function beforeMint(MintParams memory /* params */ ) external override onlyVault {}

    function afterMint(MintParams memory /* params */ ) external override onlyVault {}

    function beforeRedeem(RedeemParams memory /* params */ ) external override onlyVault {}

    function afterRedeem(RedeemParams memory /* params */ ) external override onlyVault {}

    function beforeWithdraw(WithdrawParams memory /* params */ ) external override onlyVault {}

    function afterWithdraw(WithdrawParams memory /* params */ ) external override onlyVault {}

    function beforeProcessAccounting(BeforeProcessAccountingParams memory /* params */ ) external override onlyVault {}

    function afterProcessAccounting(AfterProcessAccountingParams memory /* params */ ) external override onlyVault {}
}
