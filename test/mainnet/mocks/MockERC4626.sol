// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC4626 is ERC4626 {
    constructor(ERC20 asset_, string memory name_, string memory symbol_) ERC4626(asset_) ERC20(name_, symbol_) {}

    /**
     * @notice Slashes a fraction of the total assets and sends them to the caller
     * @dev This is a mock function that removes a fraction of the total assets
     * @param fraction The fraction of total assets to slash (1e18 = 100%)
     * @return The amount of assets slashed
     */
    function slash(uint256 fraction) external returns (uint256) {
        require(fraction > 0, "Fraction must be greater than 0");
        require(fraction <= 1e18, "Fraction must be less than or equal to 1e18");

        uint256 totalAssetAmount = totalAssets();
        uint256 amountToSlash = (totalAssetAmount * fraction) / 1e18;

        require(amountToSlash > 0, "Slash amount too small");

        // Transfer the assets to the caller
        ERC20(asset()).transfer(msg.sender, amountToSlash);

        return amountToSlash;
    }
}
