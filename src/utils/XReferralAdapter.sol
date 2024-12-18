// solhint-disable one-contract-per-file
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";

contract XReferralAdapter {

    event ReferralDepositProcessed(
        address indexed vault,
        address indexed asset,
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

    constructor() public {

    }

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
