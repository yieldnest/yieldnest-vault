// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";

import {AsyncWithdrawLib} from "src/library/AsyncWithdrawLib.sol";

contract Withdrawer is BaseStrategy {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        address withdrawalQueueManager
    ) external virtual initializer {
        _initialize(
            admin, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_, withdrawalQueueManager
        );
    }

    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        address withdrawalQueueManager
    ) internal virtual {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = countNativeAsset_;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;

        BaseStrategyStorage storage baseStrategyStorage = _getBaseStrategyStorage();
        baseStrategyStorage.withdrawalQueueManager = withdrawalQueueManager;
    }

    function _computeTotalAssets() internal view virtual override returns (uint256 totalBaseBalance) {
        return AsyncWithdrawLib.computeTotalAssets();
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    function asyncWithdrawBalance(address asset, address owner) external view returns (uint256, uint256) {
        return AsyncWithdrawLib.asyncWithdrawBalance(asset, owner);
    }
}
