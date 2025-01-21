// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {AsyncWithdrawalLib} from "src/library/AsyncWithdrawalLib.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";

contract Withdrawer is BaseStrategy {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) external virtual initializer {
        _initialize(admin, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
    }

    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
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
    }

    function _computeTotalAssets() internal view virtual override returns (uint256 totalBaseBalance) {
        return AsyncWithdrawalLib.computeTotalAssets();
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    function asyncWithdrawalBalance(address asset) external view returns (uint256) {
        return AsyncWithdrawalLib.asyncWithdrawalBalance(asset);
    }

    function getWOETHRequestIds() external view returns (uint256[] memory) {
        return OriginWithdrawalLib.getWOETHRequestIds();
    }

    function requestWithdrawalWOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256) {
        return OriginWithdrawalLib.requestWithdrawalWOETH(amount);
    }

    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        public
        onlyRole(PROCESSOR_ROLE)
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        return OriginWithdrawalLib.claimWithdrawalsWOETH(requestIds);
    }
}
