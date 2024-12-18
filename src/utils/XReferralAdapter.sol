// solhint-disable one-contract-per-file
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";

interface IKernelStrategy {
    function getHasAllocator() external view returns (bool hasAllocators);
    function hasRole(bytes32 role, address account) external view returns (bool hasRole);
}

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
    error NotAnAllocator(address);
    error NoDirectETHDeposit();

    modifier isAllocator(address _vault) {
        try IKernelStrategy(_vault).getHasAllocator() returns (bool hasAllocator) {
            if (hasAllocator) {
                if (!IKernelStrategy(_vault).hasRole(ALLOCATOR_ROLE, msg.sender)) {
                    revert NotAnAllocator(msg.sender);
                }
            }
        } catch {
            // allocator role not required
        }
        _;
    }

    constructor() public {}

    /**
     * @dev wraps the deposit for the specific strategy to emit a referal event
     * @param _vault the vault to be used
     * @param asset asset the ERC20 being deposited
     * @param amount the amount of the asset being deposited
     * @param referrer the address of the referrer
     * @param receiver the addres of the receiver
     * @return shares the shares being received
     */
    function depositAssetWithReferral(address _vault, address asset, uint256 amount, address referrer, address receiver)
        public
        isAllocator(_vault)
        returns (uint256 shares)
    {
        IVault vault = IVault(_vault);

        if (IVault(vault).asset() == address(0)) {
            revert InvalidVault(_vault);
        }
        if (amount == 0) {
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

        shares = vault.depositAsset(asset, amount, receiver);

        emit ReferralDepositProcessed(
            address(vault), asset, msg.sender, referrer, receiver, amount, shares, block.timestamp
        );
    }

    receive() external payable {
        revert NoDirectETHDeposit();
    }
}
