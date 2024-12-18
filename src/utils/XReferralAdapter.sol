// solhint-disable one-contract-per-file
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {Initializable} from "src/Common.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

contract XReferralAdapter is Initializable {
    IVault public vault;

    event ReferralDepositProcessed(
        address indexed vault,
        address indexed asset,
        address indexed depositor,
        address indexed receiver,
        uint256 amount,
        uint256 shares,
        address indexed referrer,
        uint256 timestamp
    );

    error InvalidVault(address);
    error ZeroAmount();

    constructor() public {
        _disableInitializers();
    }

    function initialize(address _vault) public initializer {
        vault = IVault(_vault);
        if (IVault(vault).asset() == address(0)) {
            revert InvalidVault(_vault);
        }
    }

    /**
     * @dev wraps the deposit for the specific strategy to include a referral id for the desiered refererr
     */
    function depositAssetWithReferral(address asset, uint256 amount, address referrer, address receiver)
        public
        returns (uint256 shares)
    {
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
            address(vault), asset, msg.sender, receiver, amount, shares, referrer, block.timestamp
        );
    }

    receive() external payable {
        revert NoDirectETHDeposit();
    }
}
