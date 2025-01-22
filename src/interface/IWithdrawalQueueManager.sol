// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IWithdrawalQueueManager {
    struct WithdrawalRequest {
        uint256 amount;
        uint256 feeAtRequestTime;
        uint256 redemptionRateAtRequestTime;
        uint256 creationTimestamp;
        bool processed;
        bytes data;
    }

    struct Finalization {
        uint64 startIndex;
        uint64 endIndex;
        uint96 redemptionRate;
    }

    struct WithdrawalClaim {
        uint256 tokenId;
        uint256 finalizationId;
        address receiver;
    }

    function REQUEST_FINALIZER_ROLE() external view returns (bytes32);
    function withdrawalFee() external view returns (uint256);
    function requestWithdrawal(uint256 amount) external returns (uint256);
    function requestWithdrawal(uint256 amount, bytes calldata data) external returns (uint256);
    function claimWithdrawal(WithdrawalClaim memory claim) external;
    function claimWithdrawal(uint256 tokenId, address receiver) external;
    function finalizeRequestsUpToIndex(uint256 _lastFinalizedIndex) external returns (uint256);
    function withdrawalRequestsForOwner(address owner)
        external
        view
        returns (uint256[] memory, WithdrawalRequest[] memory);
    function calculateFee(uint256 amount, uint256 requestWithdrawalFee) external pure returns (uint256);
    function withdrawalRequest(uint256 tokenId) external view returns (WithdrawalRequest memory request);
}

interface IAssetRegistry {
    function getAssets() external view returns (address[] memory);
}

interface IRedemptionAssetsVault {
    function redeemer() external view returns (address);
    function deposit(uint256 amount) external;
    function deposit(uint256 amount, address asset) external;
    function availableRedemptionAssets() external view returns (uint256);
    function redemptionRate() external view returns (uint256);
    function assetRegistry() external view returns (IAssetRegistry);
}
