// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {SafeERC20, IERC20} from "src/Common.sol";

contract XReferralAdapter {
    /// @notice Role for allocator permissions
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    // only 3 indexed arguments allowed in an event
    event ReferralDepositProcessed(
        address vault,
        address asset,
        address indexed depositor,
        address indexed referrer,
        address indexed receiver,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    error InvalidVault(address);
    error ZeroAmount();
    error ZeroAddress();
    error SelfReferral();

    constructor() public {}

    /**
     * @dev wraps the deposit for the specific strategy to emit a referal event
     * @param _vault the vault to be used
     * @param asset asset the ERC20 being deposited
     * @param assets the amount of the asset being deposited
     * @param referrer the address of the referrer
     * @param receiver the addres of the receiver
     * @return shares the shares being received
     */
    function depositAssetWithReferral(address _vault, address asset, uint256 assets, address referrer, address receiver)
        public
        returns (uint256 shares)
    {
        IVault vault = IVault(_vault);

        if (IVault(vault).asset() == address(0)) {
            revert InvalidVault(_vault);
        }
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (referrer == address(0)) {
            revert ZeroAddress();
        }
        if (referrer == receiver) {
            revert SelfReferral();
        }

        //transfer assets to this contract
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), assets);

        // approve vault
        SafeERC20.safeIncreaseAllowance(IERC20(asset), _vault, assets);

        shares = vault.depositAsset(asset, assets, receiver);

        emit ReferralDepositProcessed(
            address(vault), asset, msg.sender, referrer, receiver, assets, shares, block.timestamp
        );
    }
}
