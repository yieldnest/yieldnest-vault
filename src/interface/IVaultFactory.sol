// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, IERC4626, IAccessControl} from "src/Common.sol";

interface IVaultFactory is IAccessControl {
    enum VaultType {
        SingleAsset,
        MultiAsset
    }

    function timelock() external view returns (address);
    function singleVaultImpl() external view returns (address);
    function initialize(address singleVaultImpl_, address admin, address timelock_, address weth_) external;
    function createSingleVault(IERC20 asset_, string memory name_, string memory symbol_, address admin_)
        external
        returns (address);
}
