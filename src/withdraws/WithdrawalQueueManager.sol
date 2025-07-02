// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IRedeemableAsset} from "src/interface/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interface/IRedemptionAssetsVault.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721EnumerableUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

interface IWithdrawalQueueManagerEvents {
    event WithdrawalRequested(
        uint256 indexed tokenId, address indexed requester, IWithdrawalQueueManager.WithdrawalRequest request
    );
    event WithdrawalClaimed(
        uint256 indexed tokenId,
        address claimer,
        address receiver,
        IWithdrawalQueueManager.WithdrawalRequest request,
        uint256 finalizationId,
        uint256 unitOfAccountAmount,
        uint256 claimRedemptionRate
    );
    event WithdrawalFeeUpdated(uint256 newFeePercentage);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
    event SecondsToFinalizationUpdated(uint256 previousValue, uint256 newValue);
    event RequestsFinalized(
        uint256 indexed finalizationIndex,
        uint256 newFinalizedIndex,
        uint256 previousFinalizedIndex,
        uint256 redemptionRate
    );
    event SurplusRedemptionAssetsWithdrawn(uint256 amount, uint256 surplus);
}

/**
 * @title Withdrawal Queue Manager for Redeemable Assets
 * @dev Manages the queue of withdrawal requests for redeemable assets, handling fees, finalization times, and claims.
 * This contract extends ERC721 to represent each withdrawal request as a unique token.
 *
 */
contract WithdrawalQueueManager is
    IWithdrawalQueueManager,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IWithdrawalQueueManagerEvents
{
    using SafeERC20 for IRedeemableAsset;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotFinalized(uint256 tokenId);
    error ZeroAddress();
    error WithdrawalAlreadyProcessed(uint256 tokenId);
    error InsufficientBalance(uint256 currentBalance, uint256 requestedBalance);
    error CallerNotOwnerNorApproved(uint256 tokenId, address caller);
    error AmountExceedsSurplus(uint256 requestedAmount, uint256 availableSurplus);
    error AmountMustBeGreaterThanZero();
    error FeePercentageExceedsLimit();
    error ArrayLengthMismatch(uint256 length1, uint256 length2);
    error SecondsToFinalizationExceedsLimit(uint256 value);
    error WithdrawalRequestDoesNotExist(uint256 tokenId);
    error IndexExceedsTokenCount(uint256 index, uint256 tokenCount);
    error IndexNotAdvanced(uint256 newIndex, uint256 currentIndex);
    error InvalidFinalizationId(uint256 finalizationId);
    error TokenIdNotInFinalizationRange(uint256 tokenId, uint256 finalizationId, uint256 startIndex, uint256 endIndex);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Role identifier for administrators who can manage the withdrawal queue settings.
    bytes32 public constant WITHDRAWAL_QUEUE_ADMIN_ROLE = keccak256("WITHDRAWAL_QUEUE_ADMIN_ROLE");

    /// @dev Role identifier for accounts authorized to withdraw surplus redemption assets.
    bytes32 public constant REDEMPTION_ASSET_WITHDRAWER_ROLE = keccak256("REDEMPTION_ASSET_WITHDRAWER_ROLE");

    /// @dev Role identifier for accounts authorized to finalize withdrawal requests.
    bytes32 public constant REQUEST_FINALIZER_ROLE = keccak256("REQUEST_FINALIZER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 public constant FEE_PRECISION = 1000000;
    uint256 public constant MAX_SECONDS_TO_FINALIZATION = 3600 * 24 * 28; // 4 weeks

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice The asset that can be redeemed through withdrawal requests.
    IRedeemableAsset public redeemableAsset;

    /// @notice The vault where redemption assets are stored.
    IRedemptionAssetsVault public redemptionAssetsVault;

    /// @notice Counter for tracking the next token ID to be assigned.
    uint256 public _tokenIdCounter;

    /// @notice Mapping of token IDs to their corresponding withdrawal requests.
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    /// @notice The required duration in seconds between a withdrawal request and when it can be finalized.
    uint256 public secondsToFinalization;

    /// @notice The fee percentage charged on withdrawals.
    uint256 public withdrawalFee;

    /// @notice The address where withdrawal fees are sent.
    address public feeReceiver;

    /// @notice The address authorized to finalize withdrawal requests.
    address public requestFinalizer;

    /// @notice pending requested redemption amount in redemption unit of account
    uint256 public pendingRequestedRedemptionAmount;

    uint256 public lastFinalizedIndex;

    /// @notice Array to store finalization data
    Finalization[] public finalizations;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    struct Init {
        string name;
        string symbol;
        IRedeemableAsset redeemableAsset;
        IRedemptionAssetsVault redemptionAssetsVault;
        address admin;
        address withdrawalQueueAdmin;
        address redemptionAssetWithdrawer;
        uint256 withdrawalFee;
        address feeReceiver;
        address requestFinalizer;
    }

    function initialize(Init memory init)
        public
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.redeemableAsset))
        notZeroAddress(address(init.redemptionAssetsVault))
        notZeroAddress(address(init.withdrawalQueueAdmin))
        notZeroAddress(address(init.feeReceiver))
        notZeroAddress(address(init.requestFinalizer))
        initializer
    {
        __ERC721_init(init.name, init.symbol);
        redeemableAsset = init.redeemableAsset;
        redemptionAssetsVault = init.redemptionAssetsVault;

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(WITHDRAWAL_QUEUE_ADMIN_ROLE, init.withdrawalQueueAdmin);
        _grantRole(REDEMPTION_ASSET_WITHDRAWER_ROLE, init.redemptionAssetWithdrawer);
        _grantRole(REQUEST_FINALIZER_ROLE, init.requestFinalizer);

        withdrawalFee = init.withdrawalFee;
        feeReceiver = init.feeReceiver;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWAL REQUESTS  -----------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Requests a withdrawal of a specified amount of redeemable assets without additional data.
     * @dev This is a convenience function that calls the main requestWithdrawal function with empty data.
     * @param amount The amount of redeemable assets to withdraw.
     * @return tokenId The token ID associated with the withdrawal request.
     */
    function requestWithdrawal(uint256 amount) external returns (uint256 tokenId) {
        return requestWithdrawal(amount, "");
    }

    /**
     * @notice Requests a withdrawal of a specified amount of redeemable assets.
     * @dev Transfers the specified amount of redeemable assets from the sender to this contract, creates a withdrawal request,
     *      and mints a token representing this request. Emits a WithdrawalRequested event upon success.
     * @param amount The amount of redeemable assets to withdraw.
     * @param data Extra data payload associated with the request
     * @return tokenId The token ID associated with the withdrawal request.
     */
    function requestWithdrawal(uint256 amount, bytes memory data) public nonReentrant returns (uint256 tokenId) {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        redeemableAsset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentRate = redemptionAssetsVault.redemptionRate();
        tokenId = _tokenIdCounter++;
        WithdrawalRequest memory request = WithdrawalRequest({
            amount: amount,
            feeAtRequestTime: withdrawalFee,
            redemptionRateAtRequestTime: currentRate,
            creationTimestamp: block.timestamp,
            processed: false,
            data: data
        });
        withdrawalRequests[tokenId] = request;

        pendingRequestedRedemptionAmount += calculateRedemptionAmount(amount, currentRate);

        _mint(msg.sender, tokenId);

        emit WithdrawalRequested(tokenId, msg.sender, request);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  CLAIMS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Claims a withdrawal for a specific token ID and transfers the assets to the specified receiver.
     * @dev This function burns the token representing the withdrawal request and transfers the net amount
     *         after fees to the receiver.
     *      It also transfers the fee to the fee receiver.
     *      It automatically finds the finalization ID for the given token ID.
     * @param tokenId The ID of the token representing the withdrawal request.
     * @param receiver The address to which the withdrawn assets will be sent.
     */
    function claimWithdrawal(uint256 tokenId, address receiver) public nonReentrant {
        WithdrawalClaim memory claim =
            WithdrawalClaim({tokenId: tokenId, receiver: receiver, finalizationId: findFinalizationForTokenId(tokenId)});
        _claimWithdrawal(claim);
    }

    /**
     * @notice Claims a withdrawal by transferring the requested assets to the specified receiver, less any applicable fees.
     * @dev This function burns the token representing the withdrawal request and transfers the net amount after fees to the receiver.
     *      It also transfers the fee to the fee receiver.
     * @param claim The claim struct contains:
     *        the tokenId The ID of the token representing the withdrawal request,
     *        the receiver as the address to which the net amount of the withdrawal will be sent.
     *        the finalizationId for the particular finalization which denotes the rate at finalization time.
     */
    function claimWithdrawal(WithdrawalClaim memory claim) public nonReentrant {
        _claimWithdrawal(claim);
    }

    function _claimWithdrawal(WithdrawalClaim memory claim) internal {
        uint256 tokenId = claim.tokenId;
        uint256 finalizationId = claim.finalizationId;
        address receiver = claim.receiver;

        if (_ownerOf(claim.tokenId) != msg.sender && _getApproved(claim.tokenId) != msg.sender) {
            revert CallerNotOwnerNorApproved(claim.tokenId, msg.sender);
        }

        // Check if the finalization ID is valid
        if (finalizationId >= finalizations.length) {
            revert InvalidFinalizationId(finalizationId);
        }

        Finalization memory finalization = finalizations[finalizationId];

        // Check if the token ID is within the finalized range
        if (tokenId < finalization.startIndex || tokenId >= finalization.endIndex) {
            revert TokenIdNotInFinalizationRange(
                tokenId, finalizationId, finalization.startIndex, finalization.endIndex
            );
        }

        // Update the redemption rate to use the one from the finalization
        uint256 redemptionRateAtFinalization = finalization.redemptionRate;

        WithdrawalRequest memory request = withdrawalRequests[tokenId];
        if (!withdrawalRequestExists(request)) {
            revert WithdrawalRequestDoesNotExist(tokenId);
        }

        if (request.processed) {
            revert WithdrawalAlreadyProcessed(tokenId);
        }

        if (!withdrawalRequestIsFinalized(tokenId)) {
            revert NotFinalized(tokenId);
        }

        withdrawalRequests[tokenId].processed = true;
        uint256 redemptionRate = (
            request.redemptionRateAtRequestTime < redemptionRateAtFinalization
                ? request.redemptionRateAtRequestTime
                : redemptionRateAtFinalization
        );

        uint256 unitOfAccountAmount = calculateRedemptionAmount(request.amount, redemptionRate);

        pendingRequestedRedemptionAmount -= unitOfAccountAmount;

        _burn(tokenId);
        redeemableAsset.burn(request.amount);

        uint256 feeAmount = calculateFee(unitOfAccountAmount, request.feeAtRequestTime);

        uint256 currentBalance = redemptionAssetsVault.availableRedemptionAssets();
        if (currentBalance < unitOfAccountAmount) {
            revert InsufficientBalance(currentBalance, unitOfAccountAmount);
        }

        // Transfer net amount (unitOfAccountAmount - feeAmount) to the receiver
        redemptionAssetsVault.transferRedemptionAssets(receiver, unitOfAccountAmount - feeAmount, request.data);

        if (feeAmount > 0) {
            redemptionAssetsVault.transferRedemptionAssets(feeReceiver, feeAmount, request.data);
        }

        emit WithdrawalClaimed(
            tokenId, msg.sender, receiver, request, finalizationId, unitOfAccountAmount, redemptionRate
        );
    }

    /**
     * @notice Allows a batch of withdrawals to be claimed by their respective token IDs.
     * @param tokenIds An array of token IDs corresponding to the withdrawal requests to be claimed.
     * @param receivers An array of addresses to receive the claimed withdrawals.
     * @dev The length of tokenIds and receivers must be the same.
     */
    function claimWithdrawals(uint256[] calldata tokenIds, address[] calldata receivers) external {
        if (tokenIds.length != receivers.length) {
            revert ArrayLengthMismatch(tokenIds.length, receivers.length);
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimWithdrawal(tokenIds[i], receivers[i]);
        }
    }

    /**
     * @notice Allows a batch of withdrawals to be claimed by their respective token IDs.
     * @param claims An array of claims corresponding to the withdrawal requests to be claimed.
     */
    function claimWithdrawals(WithdrawalClaim[] calldata claims) external {
        for (uint256 i = 0; i < claims.length; i++) {
            WithdrawalClaim memory claim = claims[i];
            claimWithdrawal(claim);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ADMIN  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Sets the withdrawal fee percentage.
     * @param feePercentage The fee percentage in basis points.
     */
    function setWithdrawalFee(uint256 feePercentage) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        if (feePercentage > FEE_PRECISION) {
            revert FeePercentageExceedsLimit();
        }
        withdrawalFee = feePercentage;
        emit WithdrawalFeeUpdated(feePercentage);
    }

    /**
     * @notice Sets the address where withdrawal fees are sent.
     * @param _feeReceiver The address that will receive the withdrawal fees.
     */
    function setFeeReceiver(address _feeReceiver)
        external
        notZeroAddress(_feeReceiver)
        onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE)
    {
        emit FeeReceiverUpdated(feeReceiver, _feeReceiver);
        feeReceiver = _feeReceiver;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  COMPUTATIONS  ------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Calculates the redemption amount based on the provided amount and the redemption rate at the time of request.
     * @param amount The amount of the redeemable asset.
     * @param redemptionRate The redemption rate expressed in the same unit of decimals as the redeemable asset.
     * @return The calculated redemption amount, adjusted for the decimal places of the redeemable asset.
     */
    function calculateRedemptionAmount(uint256 amount, uint256 redemptionRate) public view returns (uint256) {
        return amount * redemptionRate / (10 ** redeemableAsset.decimals());
    }

    /**
     * @notice Calculates the withdrawal fee based on the amount and the current fee percentage.
     * @param amount The amount from which the fee should be calculated.
     * @param requestWithdrawalFee The current fee percentage in basis points.
     * @return fee The calculated fee.
     */
    function calculateFee(uint256 amount, uint256 requestWithdrawalFee) public pure returns (uint256) {
        return (amount * requestWithdrawalFee) / FEE_PRECISION;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  REDEMPTION ASSETS  -------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Calculates the surplus of redemption assets after accounting for all pending withdrawals.
     * @return surplus The amount of surplus redemption assets in the unit of account.
     */
    function surplusRedemptionAssets() public view returns (uint256) {
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets();
        if (availableAmount > pendingRequestedRedemptionAmount) {
            return availableAmount - pendingRequestedRedemptionAmount;
        }

        return 0;
    }

    /**
     * @notice Calculates the deficit of redemption assets after accounting for all pending withdrawals.
     * @return deficit The amount of deficit redemption assets in the unit of account.
     */
    function deficitRedemptionAssets() public view returns (uint256) {
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets();
        if (pendingRequestedRedemptionAmount > availableAmount) {
            return pendingRequestedRedemptionAmount - availableAmount;
        }

        return 0;
    }

    /**
     * @notice Withdraws surplus redemption assets to a specified address.
     */
    function withdrawSurplusRedemptionAssets(uint256 amount) external onlyRole(REDEMPTION_ASSET_WITHDRAWER_ROLE) {
        uint256 surplus = surplusRedemptionAssets();
        if (amount > surplus) {
            revert AmountExceedsSurplus(amount, surplus);
        }
        redemptionAssetsVault.withdrawRedemptionAssets(amount);

        emit SurplusRedemptionAssetsWithdrawn(amount, surplus);
    }
    //--------------------------------------------------------------------------------------
    //----------------------------------  FINALITY  ----------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Checks if a withdrawal request with a given index is finalized.
     * @param index The index of the withdrawal request.
     * @return True if the request is finalized, false otherwise.
     */
    function withdrawalRequestIsFinalized(uint256 index) public view returns (bool) {
        return index < lastFinalizedIndex;
    }

    /**
     * @notice Marks all requests whose index is less than lastFinalizedIndex as finalized.
     *            The current redemptionRate rated is recorded as the finalization redemption rate.
     * @param _lastFinalizedIndex The index up to which withdrawal requests are considered finalized.
     * @dev A lastFinalizedIndex = 0 means no requests are processed. lastFinalizedIndex = 2 means
     *         requests 0 and 1 are processed.
     */
    function finalizeRequestsUpToIndex(uint256 _lastFinalizedIndex)
        external
        onlyRole(REQUEST_FINALIZER_ROLE)
        returns (uint256 finalizationIndex)
    {
        uint256 currentRate = redemptionAssetsVault.redemptionRate();

        // Create a new Finalization struct
        Finalization memory newFinalization = Finalization({
            startIndex: SafeCast.toUint64(lastFinalizedIndex),
            endIndex: SafeCast.toUint64(_lastFinalizedIndex),
            redemptionRate: SafeCast.toUint96(currentRate)
        });

        finalizationIndex = finalizations.length;

        // Add the new Finalization to the array
        finalizations.push(newFinalization);

        if (_lastFinalizedIndex > _tokenIdCounter) {
            revert IndexExceedsTokenCount(_lastFinalizedIndex, _tokenIdCounter);
        }
        if (_lastFinalizedIndex <= lastFinalizedIndex) {
            revert IndexNotAdvanced(_lastFinalizedIndex, lastFinalizedIndex);
        }
        emit RequestsFinalized(finalizationIndex, _lastFinalizedIndex, lastFinalizedIndex, currentRate);

        lastFinalizedIndex = _lastFinalizedIndex;
    }

    /**
     * @notice Finds the finalization ID for a given token ID using binary search.
     * @param tokenId The token ID to find the finalization for.
     * @return finalizationId The ID of the finalization that includes the given token ID.
     * @dev The complexity of this algorithm is Math.log2(n) and it is UNBOUNDED
     */
    function findFinalizationForTokenId(uint256 tokenId) public view returns (uint256 finalizationId) {
        uint256 finalizationsLength = finalizations.length;
        if (finalizationsLength == 0) {
            revert NotFinalized(tokenId);
        }

        uint256 left = 0;
        uint256 right = finalizationsLength - 1;

        while (left <= right) {
            uint256 mid = (left + right) / 2;
            Finalization memory finalization = finalizations[mid];

            if (tokenId >= finalization.startIndex && tokenId < finalization.endIndex) {
                return mid;
            } else if (tokenId < finalization.startIndex) {
                right = mid - 1;
            } else {
                left = mid + 1;
            }
        }

        revert NotFinalized(tokenId);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Returns the details of a withdrawal request.
     * @param tokenId The token ID of the withdrawal request.
     * @return request The withdrawal request details.
     */
    function withdrawalRequest(uint256 tokenId) public view returns (WithdrawalRequest memory request) {
        request = withdrawalRequests[tokenId];
        if (!withdrawalRequestExists(request)) {
            revert WithdrawalRequestDoesNotExist(tokenId);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Checks if a withdrawal request exists.
     * @param request The withdrawal request to check.
     * @return True if the request exists, false otherwise.
     * @dev Reverts with WithdrawalRequestDoesNotExist if the request does not exist.
     */
    function withdrawalRequestExists(WithdrawalRequest memory request) internal view returns (bool) {
        return request.creationTimestamp > 0;
    }

    function withdrawalRequestsForOwner(address owner)
        public
        view
        returns (uint256[] memory withdrawalIndexes, WithdrawalRequest[] memory requests)
    {
        uint256 tokenCount = balanceOf(owner);
        if (tokenCount == 0) {
            return (new uint256[](0), new WithdrawalRequest[](0));
        } else {
            withdrawalIndexes = new uint256[](tokenCount);
            requests = new WithdrawalRequest[](tokenCount);
            for (uint256 i = 0; i < tokenCount; i++) {
                uint256 tokenId = tokenOfOwnerByIndex(owner, i);
                withdrawalIndexes[i] = tokenId;
                requests[i] = withdrawalRequests[tokenId];
            }
            return (withdrawalIndexes, requests);
        }
    }

    /**
     * @notice Returns the details of a finalization.
     * @param finalizationId The ID of the finalization.
     * @return finalization The finalization details.
     */
    function getFinalization(uint256 finalizationId) public view returns (Finalization memory finalization) {
        if (finalizationId >= finalizations.length) {
            revert InvalidFinalizationId(finalizationId);
        }
        finalization = finalizations[finalizationId];
    }

    /**
     * @notice Returns the total number of finalizations.
     * @return count The number of finalizations.
     */
    function finalizationsCount() public view returns (uint256 count) {
        return finalizations.length;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Ensure that the given address is not the zero address.
     * @param _address The address to check.
     */
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
