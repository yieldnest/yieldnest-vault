// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract ExoVault is Initializable, ERC4626Upgradeable {

    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) public initializer {
        __ERC4626_init(asset_);
        __ERC20_init(name_, symbol_);
    }

    // Contract implementation will go here
}
