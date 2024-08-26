// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    TimelockControllerUpgradeable,
    IERC20
} from "src/Common.sol";

import {ISingleVault} from "src/ISingleVault.sol";

contract SingleVault is ISingleVault, ERC4626Upgradeable, TimelockControllerUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the SingleVault contract.
     * @param asset_ The address of the ERC20 asset.
     * @param name_ The name of the ERC20 asset.
     * @param symbol_ The symbol of the ERC20 asset.
     * @param admin_ The address of the admin.
     * @param operator_ The address of the operator.
     * @param minDelay_ The minimum delay for timelock.
     * @param proposers_ The addresses of the proposers.
     * @param executors_ The addresses of the executors.
     */
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address operator_,
        uint256 minDelay_,
        address[] calldata proposers_,
        address[] calldata executors_
    ) public initializer {
        _verifyParamsAreValid(asset_, name_, symbol_, admin_, operator_, proposers_, executors_);

        __TimelockController_init(minDelay_, proposers_, executors_, admin_);
        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(OPERATOR_ROLE, operator_);
    }

    function _verifyParamsAreValid(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address operator_,
        address[] memory proposers_,
        address[] memory executors_
    ) internal pure {
        require(asset_ != IERC20(address(0)), "Asset cannot be zero address");
        require(bytes(name_).length > 0, "Name cannot be empty");
        require(bytes(symbol_).length > 0, "Symbol cannot be empty");
        require(admin_ != address(0), "Admin cannot be zero address");
        require(operator_ != address(0), "Operator cannot be zero address");
        require(proposers_.length > 0, "Proposers cannot be empty");
        require(executors_.length > 0, "Executors cannot be empty");
    }
}
