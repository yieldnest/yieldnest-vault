// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

library StrategyLib {
    /// @notice Role for allocator permissions
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    /// @notice Role for allocator manager permissions
    bytes32 public constant ALLOCATOR_MANAGER_ROLE = keccak256("ALLOCATOR_MANAGER_ROLE");
    /// @notice Role for deposit manager permissions
    bytes32 public constant DEPOSIT_MANAGER_ROLE = keccak256("DEPOSIT_MANAGER_ROLE");

    /// @notice Storage structure for strategy-specific parameters
    struct BaseStrategyStorage {
        bool hasAllocators;
    }

    /// @notice Storage structure for strategy-specific parameters
    struct SyncStrategyStorage {
        bool syncDeposit;
        bool syncWithdraw;
    }

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function getBaseStrategyStorage() public pure returns (BaseStrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy.base")
            $.slot := 0x5cfdf694cb3bdee9e4b3d9c4b43849916bf3f018805254a1c0e500548c668500
        }
    }

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function getSyncStrategyStorage() public pure returns (SyncStrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy.sync")
            $.slot := 0x023d1cf75a0b8417c3b567b13742795389a9b4d09bd3ca14ffeda95bbf3e6f7a
        }
    }
}
