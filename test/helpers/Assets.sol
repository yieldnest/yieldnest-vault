// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { IERC20 } from "src/Common.sol";
import { BscContracts } from "script/Contracts.sol";

import "forge-std/Test.sol";

contract AssetHelper is Test, BscContracts {

    address silsBNB_WHALE = 0x6F28FeC449dbd2056b76ac666350Af8773E03873;

    function get_silsBNB(address user, uint256 amount) public {
        IERC20 silsBNB = IERC20(silsBNB);
        vm.startPrank(silsBNB_WHALE);
        silsBNB.approve(user, amount);
        silsBNB.transfer(user, amount);
    }
}