// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface IRedemptionAssetsVault {
    function redeemer() external view returns (address);
    function deposit(uint256 amount) external;
    function availableRedemptionAssets() external view returns (uint256);
    function redemptionRate() external view returns (uint256);
}

interface IWithdrawalQueueManager is IERC721 {
    // Structs
    struct WithdrawalRequest {
        uint256 amount;
        uint256 feeAtRequestTime;
        uint256 redemptionRateAtRequestTime;
        uint256 creationTimestamp;
        bool processed;
        bytes data;
    }

    struct WithdrawalClaim {
        uint256 tokenId;
        address receiver;
        uint256 finalizationId;
    }

    struct Finalization {
        uint64 startIndex;
        uint64 endIndex;
        uint96 redemptionRate;
    }

    // Events
    event WithdrawalRequested(uint256 indexed tokenId, address indexed requester, WithdrawalRequest request);

    event WithdrawalClaimed(
        uint256 indexed tokenId,
        address claimer,
        address receiver,
        WithdrawalRequest request,
        uint256 finalizationId,
        uint256 unitOfAccountAmount,
        uint256 claimRedemptionRate
    );

    event WithdrawalFeeUpdated(uint256 newFeePercentage);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
    event RequestsFinalized(
        uint256 indexed finalizationIndex,
        uint256 newFinalizedIndex,
        uint256 previousFinalizedIndex,
        uint256 redemptionRate
    );
    event SurplusRedemptionAssetsWithdrawn(uint256 amount, uint256 surplus);

    // Core Functions
    function requestWithdrawal(uint256 amount) external returns (uint256 tokenId);
    function requestWithdrawal(uint256 amount, bytes memory data) external returns (uint256 tokenId);
    function claimWithdrawal(uint256 tokenId, address receiver) external;
    function claimWithdrawal(WithdrawalClaim memory claim) external;
    function claimWithdrawals(uint256[] calldata tokenIds, address[] calldata receivers) external;
    function claimWithdrawals(WithdrawalClaim[] calldata claims) external;

    // Admin Functions
    function setWithdrawalFee(uint256 feePercentage) external;
    function setFeeReceiver(address _feeReceiver) external;
    function withdrawSurplusRedemptionAssets(uint256 amount) external;
    function finalizeRequestsUpToIndex(uint256 _lastFinalizedIndex) external returns (uint256 finalizationIndex);

    // View Functions
    function withdrawalRequest(uint256 tokenId) external view returns (WithdrawalRequest memory request);
    function withdrawalRequestExists(WithdrawalRequest memory request) external view returns (bool);
    function withdrawalRequestIsFinalized(uint256 index) external view returns (bool);
    function withdrawalRequestsForOwner(address owner)
        external
        view
        returns (uint256[] memory withdrawalIndexes, WithdrawalRequest[] memory requests);
    function findFinalizationForTokenId(uint256 tokenId) external view returns (uint256 finalizationId);
    function getFinalization(uint256 finalizationId) external view returns (Finalization memory finalization);
    function finalizationsCount() external view returns (uint256 count);
    function surplusRedemptionAssets() external view returns (uint256);
    function deficitRedemptionAssets() external view returns (uint256);
    function redemptionAssetsVault() external view returns (IRedemptionAssetsVault);
    // State Variables Getters
    function withdrawalFee() external view returns (uint256);
    function feeReceiver() external view returns (address);
    function lastFinalizedIndex() external view returns (uint256);
    function pendingRequestedRedemptionAmount() external view returns (uint256);
    function FEE_PRECISION() external view returns (uint256);
    function calculateFee(uint256 amount, uint256 feeAtRequestTime) external view returns (uint256);
    function requestFinalizer() external view returns (address);
    function redeemableAsset() external view returns (address);
}
