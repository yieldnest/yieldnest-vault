// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ERC4626Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IERC20, Math} from "src/Common.sol";

import {ISingleVault} from "src/interface/ISingleVault.sol";

/* ynETH Pre-Launch Vault */

contract SingleVault is ISingleVault, ERC4626Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using Math for uint256;

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset_, string memory name_, string memory symbol_, address admin_) public initializer {
        _verifyParamsAreValid(asset_, name_, symbol_, admin_);
        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    receive() external payable nonReentrant {
        if (msg.value > 0) {
            _mintSharesForETH(msg.value);
        }
    }

    fallback() external payable nonReentrant {
        if (msg.value > 0) {
            _mintSharesForETH(msg.value);
        }
    }

    function _mintSharesForETH(uint256 amount) private {
        IERC20 weth = _retrieveERC4626Storage()._asset;

        (bool success,) = address(weth).call{value: amount}("");
        if (!success) revert DepositFailed();

        if (msg.sender != address(this)) {
            _mint(msg.sender, amount);
        }
    }

    function _verifyParamsAreValid(IERC20 asset_, string memory name_, string memory symbol_, address admin_)
        internal
        pure
    {
        if (asset_ == IERC20(address(0))) revert AssetZeroAddress();
        if (bytes(name_).length == 0) revert NameEmpty();
        if (bytes(symbol_).length == 0) revert SymbolEmpty();
        if (admin_ == address(0)) revert AdminZeroAddress();
    }

    function _retrieveERC4626Storage() internal pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }
}
