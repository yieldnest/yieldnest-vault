// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract MetaVaultScript is Test {
    function testComputeMetaVaultHash() external pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256("yieldnest.storage.metavault")) - 1)) & ~bytes32(uint256(0xff));
    }
}