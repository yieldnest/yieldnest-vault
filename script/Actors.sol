/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IActors {
    function ADMIN() external view returns (address);
    function UNAUTHORIZED() external view returns (address);
    function PROPOSER_1() external view returns (address);
    function PROPOSER_2() external view returns (address);
    function EXECUTOR_1() external view returns (address);
    function EXECUTOR_2() external view returns (address);

    /// @dev timelock
    function FEE_MANAGER() external view returns (address);
    /// @dev timelock
    function PROVIDER_MANAGER() external view returns (address);
    /// @dev timelock
    function BUFFER_MANAGER() external view returns (address);
    /// @dev timelock
    function ASSET_MANAGER() external view returns (address);
    /// @dev timelock
    function PROCESSOR_MANAGER() external view returns (address);
    /// @dev multisig
    function PAUSER() external view returns (address);
    /// @dev multisig
    function UNPAUSER() external view returns (address);
    /// @dev multisig
    function PROCESSOR() external view returns (address);
}

contract TestnetActors is IActors {
    // solhint-disable-next-line const-name-snakecase
    address public constant YnSecurityCouncil = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    address public constant ADMIN = YnSecurityCouncil;
    address public constant UNAUTHORIZED = address(0);
    address public constant PROCESSOR = YnSecurityCouncil;
    address public constant PROPOSER_1 = YnSecurityCouncil;
    address public constant PROPOSER_2 = YnSecurityCouncil;
    address public constant EXECUTOR_1 = YnSecurityCouncil;
    address public constant EXECUTOR_2 = YnSecurityCouncil;

    address public constant FEE_MANAGER = YnSecurityCouncil;
    address public constant PROVIDER_MANAGER = YnSecurityCouncil;
    address public constant BUFFER_MANAGER = YnSecurityCouncil;
    address public constant ASSET_MANAGER = YnSecurityCouncil;
    address public constant PROCESSOR_MANAGER = YnSecurityCouncil;
    address public constant PAUSER = YnSecurityCouncil;
    address public constant UNPAUSER = YnSecurityCouncil;
}

contract MainnetActors is IActors {
    // solhint-disable-next-line const-name-snakecase
    address public constant YnSecurityCouncil = 0x721688652DEa9Cabec70BD99411EAEAB9485d436;

    address public constant ADMIN = YnSecurityCouncil;
    address public constant UNAUTHORIZED = address(0);
    address public constant PROCESSOR = 0x258d7614d9c608D191A8a103f95B7Df066a19bbF;
    address public constant EXECUTOR_1 = YnSecurityCouncil;
    address public constant PROPOSER_1 = YnSecurityCouncil;
    address public constant EXECUTOR_2 = YnSecurityCouncil;
    address public constant PROPOSER_2 = YnSecurityCouncil;

    address public constant FEE_MANAGER = YnSecurityCouncil;
    address public constant PROVIDER_MANAGER = YnSecurityCouncil;
    address public constant BUFFER_MANAGER = YnSecurityCouncil;
    address public constant ASSET_MANAGER = YnSecurityCouncil;
    address public constant PROCESSOR_MANAGER = YnSecurityCouncil;
    address public constant PAUSER = 0x7B4B43f00cf80AABda8F72d61b129F1e7F86fCaF;
    address public constant UNPAUSER = YnSecurityCouncil;
}
