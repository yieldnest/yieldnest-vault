// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title Security Fixes for BaseStrategy.sol
 * @notice This file contains the recommended fixes for security issues identified in BaseStrategy.sol
 * @dev Apply these fixes to src/strategy/BaseStrategy.sol
 */

// ============================================================================
// FIX #1: Secure onlyAllocator Modifier
// ============================================================================

/**
 * BEFORE (VULNERABLE):
 * modifier onlyAllocator() {
 *     if (_getBaseStrategyStorage().hasAllocators && !hasRole(ALLOCATOR_ROLE, msg.sender)) {
 *         revert AccessControlUnauthorizedAccount(msg.sender, ALLOCATOR_ROLE);
 *     }
 *     _;
 * }
 */

/**
 * AFTER (SECURE):
 */
modifier onlyAllocator() {
    BaseStrategyStorage storage $ = _getBaseStrategyStorage();
    if (!$hasAllocators) {
        revert AllocatorsNotEnabled();
    }
    if (!hasRole(ALLOCATOR_ROLE, msg.sender)) {
        revert AccessControlUnauthorizedAccount(msg.sender, ALLOCATOR_ROLE);
    }
    _;
}

// Add to IBaseStrategy interface:
// error AllocatorsNotEnabled();

// ============================================================================
// FIX #2: Secure withdrawAsset Function
// ============================================================================

/**
 * BEFORE (VULNERABLE):
 * function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
 *     public
 *     virtual
 *     override(BaseVault, IBaseStrategy)
 *     nonReentrant
 *     returns (uint256 shares)
 * {
 *     shares = _withdrawAsset(asset_, assets, receiver, owner);
 * }
 */

/**
 * AFTER (SECURE):
 */
function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
    public
    virtual
    override(BaseVault, IBaseStrategy)
    onlyRole(ALLOCATOR_ROLE)  // Add explicit role check
    nonReentrant
    returns (uint256 shares)
{
    BaseStrategyStorage storage $ = _getBaseStrategyStorage();
    if (!$hasAllocators) {
        revert AllocatorsNotEnabled();
    }
    shares = _withdrawAsset(asset_, assets, receiver, owner);
}

// ============================================================================
// FIX #3: Add Asset Validation to setAssetWithdrawable
// ============================================================================

/**
 * BEFORE (VULNERABLE):
 * function setAssetWithdrawable(address asset_, bool withdrawable_) 
 *     external 
 *     onlyRole(ASSET_MANAGER_ROLE) 
 * {
 *     _setAssetWithdrawable(asset_, withdrawable_);
 * }
 */

/**
 * AFTER (SECURE):
 */
function setAssetWithdrawable(address asset_, bool withdrawable_) 
    external 
    onlyRole(ASSET_MANAGER_ROLE) 
{
    if (asset_ == address(0)) {
        revert ZeroAddress();
    }
    if (!hasAsset(asset_)) {
        revert InvalidAsset(asset_);
    }
    _setAssetWithdrawable(asset_, withdrawable_);
}

// ============================================================================
// FIX #4: Improve _availableAssets Documentation
// ============================================================================

/**
 * BEFORE (INCOMPLETE):
 * function _availableAssets(address asset_) internal view virtual returns (uint256 availableAssets) {
 *     availableAssets = IERC20(asset_).balanceOf(address(this));
 * }
 */

/**
 * AFTER (DOCUMENTED):
 */
/**
 * @notice Internal function to get the available amount of assets.
 * @param asset_ The address of the asset.
 * @return availableAssets The available amount of assets.
 * @dev CRITICAL: Concrete strategies MUST override this function to include:
 *      - Contract balance: IERC20(asset_).balanceOf(address(this))
 *      - Assets deployed to external protocols (staking, lending, etc.)
 *      - Assets available for immediate withdrawal
 *      - Any other sources of immediately available assets
 *      
 *      This function is used by maxWithdraw() and maxRedeem() to calculate
 *      withdrawal limits. Incorrect implementation can lead to:
 *      - Users unable to withdraw their fair share
 *      - DoS attacks
 *      - Incorrect accounting
 *      
 *      Example override:
 *      ```solidity
 *      function _availableAssets(address asset_) internal view override returns (uint256) {
 *          uint256 balance = IERC20(asset_).balanceOf(address(this));
 *          uint256 staked = stakingContract.balanceOf(address(this));
 *          uint256 available = stakingContract.availableForWithdrawal(address(this));
 *          return balance + staked + available;
 *      }
 *      ```
 */
function _availableAssets(address asset_) internal view virtual returns (uint256 availableAssets) {
    availableAssets = IERC20(asset_).balanceOf(address(this));
    // NOTE: This base implementation only returns contract balance.
    // Concrete strategies MUST override to include deployed assets.
}

// ============================================================================
// FIX #5: Add Safety Check to previewRedeemAsset
// ============================================================================

/**
 * BEFORE (POTENTIALLY UNSAFE):
 * function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
 *     (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
 *     assets = assets - _feeOnTotal(assets, _msgSender());
 * }
 */

/**
 * AFTER (SAFE):
 */
function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
    (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
    uint256 fee = _feeOnTotal(assets, _msgSender());
    
    // Safety check (should never trigger, but protects against bugs)
    if (assets < fee) {
        revert InsufficientAssetsForFee(assets, fee);
    }
    
    assets = assets - fee;
}

// Add error to interface:
// error InsufficientAssetsForFee(uint256 assets, uint256 fee);

// ============================================================================
// FIX #6: Improve setHasAllocator with Better Events
// ============================================================================

/**
 * BEFORE (BASIC):
 * function setHasAllocator(bool hasAllocators_) external onlyRole(ALLOCATOR_MANAGER_ROLE) {
 *     _setHasAllocator(hasAllocators_);
 * }
 */

/**
 * AFTER (ENHANCED):
 */
function setHasAllocator(bool hasAllocators_) external onlyRole(ALLOCATOR_MANAGER_ROLE) {
    BaseStrategyStorage storage $ = _getBaseStrategyStorage();
    bool oldValue = $.hasAllocators;
    
    _setHasAllocator(hasAllocators_);
    
    // Emit warning if disabling allocators
    if (!hasAllocators_ && oldValue) {
        emit AllocatorsDisabledWarning(msg.sender, block.timestamp);
    }
}

// Add event to interface:
// event AllocatorsDisabledWarning(address indexed caller, uint256 timestamp);

// ============================================================================
// FIX #7: Gas Optimization - Cache Storage Pointers
// ============================================================================

/**
 * BEFORE (INEFFICIENT):
 * function _maxWithdrawAsset(address asset_, address owner) internal view virtual returns (uint256 maxAssets) {
 *     if (paused() || !_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
 *         return 0;
 *     }
 *     uint256 availableAssets = _availableAssets(asset_);
 *     maxAssets = previewRedeemAsset(asset_, balanceOf(owner));
 *     maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
 * }
 */

/**
 * AFTER (OPTIMIZED):
 */
function _maxWithdrawAsset(address asset_, address owner) internal view virtual returns (uint256 maxAssets) {
    BaseStrategyStorage storage $ = _getBaseStrategyStorage();
    if (paused() || !$.isAssetWithdrawable[asset_]) {
        return 0;
    }
    uint256 availableAssets = _availableAssets(asset_);
    maxAssets = previewRedeemAsset(asset_, balanceOf(owner));
    maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
}

// Apply same optimization to:
// - _maxRedeemAsset()
// - _withdrawAsset()
// - Any function calling _getBaseStrategyStorage() multiple times

// ============================================================================
// COMPLETE UPDATED INTERFACE ADDITIONS
// ============================================================================

/**
 * Add these to src/interface/IBaseStrategy.sol:
 */

/*
interface IBaseStrategy {
    // ... existing code ...
    
    // Add new errors:
    error AllocatorsNotEnabled();
    error InsufficientAssetsForFee(uint256 assets, uint256 fee);
    
    // Add new events:
    event AllocatorsDisabledWarning(address indexed caller, uint256 timestamp);
    
    // ... rest of interface ...
}
*/
