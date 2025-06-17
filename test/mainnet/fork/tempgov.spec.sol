// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Vault} from "src/Vault.sol";
import {ProxyAdmin, Math} from "src/Common.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Vault} from "src/Vault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {console} from "lib/forge-std/src/console.sol";

contract YnBNBxForkTest is BaseIntegrationTest {
    IERC20 public wbnb;

    function setUp() public virtual override {
        super.setUp();
        wbnb = IERC20(MainnetContracts.WBNB);

        // verify alwaysComputeTotalAssets is true
        assertTrue(vault.alwaysComputeTotalAssets(), "alwaysComputeTotalAssets should be true");
    }

    function testFinishGovProposal() public {

        address[] memory targets = new address[](2);
        targets[0] = 0x32C830f5c34122C6afB8aE87ABA541B7900a2C5F;
        targets[1] = 0x32C830f5c34122C6afB8aE87ABA541B7900a2C5F;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = hex"cfd8d6c000000000000000000000000075cdf94cb930bd6d65617546b9901c36c41b8c36";
        payloads[1] = hex"28f256b40000000000000000000000008e01db38a409d6e6b8a81fd21d84e05912e8730a0000000000000000000000000000000000000000000000000000000000000000";

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        uint256 delay = 86400;


        vm.warp(block.timestamp + delay);

        TimelockController timelock = TimelockController(payable(0x2F3fEdd2F6EC681D9Cc2ecC688d8C7286Eca1F40));
        vm.startPrank(MainnetActors.ADMIN);
        timelock.executeBatch(targets, values, payloads, predecessor, salt);
        vm.stopPrank();


        IVault.AssetParams memory assetParams = vault.getAsset(0x8E01DB38a409D6E6B8A81fd21d84E05912e8730A);
        console.log("Asset active:", assetParams.active);
        console.log("Asset index:", assetParams.index);
        console.log("Asset decimals:", assetParams.decimals);

        console.log("Total Assets:", vault.totalAssets());
        console.log("Total Supply:", vault.totalSupply());
    }
}