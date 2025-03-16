// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MockProvider} from "test/unit/mocks/MockProvider.sol";

/**
 * @title Mock6DecimalsProvider
 * @notice A mock provider implementation that uses 6 decimals for rate offset
 * @dev This extends MockProvider but overrides the rateOffset to return 1e12
 */
contract Mock6DecimalsProvider is MockProvider {
    /**
     * @notice Returns the rate offset used for rate calculations
     * @dev Overrides the parent implementation to return 1e12 (for 6 decimals)
     * @return The rate offset value as a uint256
     */
    function rateOffset() public pure override returns (uint256) {
        return 1e12;
    }
}
