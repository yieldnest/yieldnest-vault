// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "src/Common.sol";
import {BscContracts} from "script/Contracts.sol";

import "forge-std/Test.sol";

contract AssetHelper is Test, BscContracts {
    address slisBNB_WHALE = 0x6F28FeC449dbd2056b76ac666350Af8773E03873;

    function get_slisBNB(address user, uint256 amount) public {
        IERC20 slisBNB = IERC20(slisBNB);
        vm.startPrank(slisBNB_WHALE);
        slisBNB.approve(user, amount);
        slisBNB.transfer(user, amount);
    }
}
