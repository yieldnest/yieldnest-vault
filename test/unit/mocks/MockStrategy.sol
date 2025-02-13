// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";

contract MockStrategy is BaseStrategy {
    function initialize(string memory name, string memory symbol, address admin, bool alwaysComputeTotalAssets_)
        external
        initializer
    {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = false;
        vaultStorage.decimals = 18;
        vaultStorage.countNativeAsset = true;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }
}
