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

    function beforeDeposit(
        address, /* asset */
        uint256, /* assets */
        address, /* caller */
        address, /* receiver */
        uint256, /* shares */
        uint256 /* baseAssets */
    ) external override onlyVault {}

    function afterDeposit(
        address, /* asset */
        uint256, /* assets */
        address, /* caller */
        address, /* receiver */
        uint256, /* shares */
        uint256 /* baseAssets */
    ) external override onlyVault {}

    function beforeMint(
        address, /* asset */
        uint256, /* shares */
        address, /* caller */
        address, /* receiver */
        uint256, /* assets */
        uint256 /* baseAssets */
    ) external override onlyVault {}

    function afterMint(
        address, /* asset */
        uint256, /* shares */
        address, /* caller */
        address, /* receiver */
        uint256, /* assets */
        uint256 /* baseAssets */
    ) external override onlyVault {}

    function beforeRedeem(
        address, /* asset */
        uint256, /* shares */
        address, /* caller */
        address, /* receiver */
        address, /* owner */
        uint256 /* assets */
    ) external override onlyVault {}

    function afterRedeem(
        address, /* asset */
        uint256, /* shares */
        address, /* caller */
        address, /* receiver */
        address, /* owner */
        uint256 /* assets */
    ) external override onlyVault {}

    function beforeWithdraw(
        address, /* asset */
        uint256, /* assets */
        address, /* caller */
        address, /* receiver */
        address, /* owner */
        uint256 /* shares */
    ) external override onlyVault {}

    function afterWithdraw(
        address, /* asset */
        uint256, /* assets */
        address, /* caller */
        address, /* receiver */
        address, /* owner */
        uint256 /* shares */
    ) external override onlyVault {}

    function beforeProcessAccounting(
        uint256, /* totalAssetsBeforeAccounting */
        uint256, /* totalSupplyBeforeAccounting */
        uint256 /* totalBaseAssetsBeforeAccounting */
    ) external override onlyVault {}

    function afterProcessAccounting(
        uint256, /* totalAssetsBeforeAccounting */
        uint256, /* totalAssetsAfterAccounting */
        uint256, /* totalSupplyBeforeAccounting */
        uint256, /* totalSupplyAfterAccounting */
        uint256, /* totalBaseAssetsAfterAccounting */
        uint256 /* totalBaseAssetsBeforeAccounting */
    ) external override onlyVault {}
}
