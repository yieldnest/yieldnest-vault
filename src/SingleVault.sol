// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    TimelockControllerUpgradeable,
    IERC20,
    IERC4626
} from "src/Common.sol";

import {ISingleVault} from "src/ISingleVault.sol";

contract SingleVault is ISingleVault, ERC4626Upgradeable, TimelockControllerUpgradeable, ReentrancyGuardUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the SingleVault contract.
     * @param asset_ The address of the ERC20 asset.
     * @param name_ The name of the vault.
     * @param symbol_ The symbol of the vault.
     * @param admin_ The address of the admin.
     * @param minDelay_ The minimum delay for timelock.
     * @param proposers_ The addresses of the proposers.
     * @param executors_ The addresses of the executors.
     */
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        uint256 minDelay_,
        address[] calldata proposers_,
        address[] calldata executors_
    ) public initializer {
        _verifyParamsAreValid(asset_, name_, symbol_, admin_, proposers_, executors_);
        __TimelockController_init(minDelay_, proposers_, executors_, admin_);
        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function _verifyParamsAreValid(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address[] memory proposers_,
        address[] memory executors_
    ) internal pure {
        if (asset_ == IERC20(address(0))) revert AssetZeroAddress();
        if (bytes(name_).length == 0) revert NameEmpty();
        if (bytes(symbol_).length == 0) revert SymbolEmpty();
        if (admin_ == address(0)) revert AdminZeroAddress();
        if (proposers_.length == 0) revert ProposersEmpty();
        if (executors_.length == 0) revert ExecutorsEmpty();
    }
}
