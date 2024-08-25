// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SingleVault} from "./SingleVault.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract VaultFactory {
    event NewVault(address indexed vault);

    error SymbolTaken();

    struct Vault {
        address vault;
        string name;
        string symbol;
    }

    mapping(string => Vault) public vaults;

    function createSingleVault(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address operator_
    ) public returns (address) {
        if (vaults[symbol_].vault != address(0)) revert SymbolTaken();

        SingleVault vaultImplementation = new SingleVault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(vaultImplementation),
            address(this),
            abi.encodeWithSignature(
                "initialize(address,string,string,address,address)", asset_, name_, symbol_, admin_, operator_
            )
        );

        vaults[symbol_] = Vault(address(proxy), name_, symbol_);

        emit NewVault(address(proxy));
        return address(proxy);
    }
}
