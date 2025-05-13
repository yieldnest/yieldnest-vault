// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IKernelConfig is IAccessControl {
    /* Events
    ***********************************************************************************************************/

    // functionality has been paused
    event FunctionalityPaused(string key);

    // functionality has been unpaused
    event FunctionalityUnpaused(string key);

    // set contract to config
    event SetContract(string key, address addr);

    /* Errors
    ***********************************************************************************************************/

    /// A functionality was found paused
    error FunctionalityIsPaused(string);

    /// Function argument was invalid
    error InvalidArgument(string);

    /// The protocol was paused
    error ProtocolIsPaused();

    /// The address didn't have the ADMIN role
    error NotAdmin();

    /// The address didn't have the MANAGER role
    error NotManager();

    /// The address didn't have the UPGRADER role
    error NotUpgrader();

    /// A sensitive key-value (eg. an address) in config was not stored
    error NotStored(string);

    /* External Functions
    ***********************************************************************************************/

    function check() external view returns (bool);

    function getAssetRegistry() external view returns (address);

    function getClisBnbAddress() external view returns (address);

    function getHelioProviderAddress() external view returns (address);

    function getStakerGateway() external view returns (address);

    function getWBNBAddress() external view returns (address);

    function initialize(address adminAddr, address wbnbAddress) external;

    function isFunctionalityPaused(string memory key, bool includeProtocol) external view returns (bool);

    function isProtocolPaused() external view returns (bool);

    function pauseFunctionality(string calldata key) external;

    function requireFunctionalityVaultsDepositNotPaused() external view;

    function requireFunctionalityVaultsWithdrawNotPaused() external view;

    function requireRoleUpgrader(address addr) external view;

    function requireRoleAdmin(address addr) external view;

    function requireRoleManager(address addr) external view;

    function setAddress(string calldata key, address addr) external;

    function unpauseFunctionality(string calldata key) external;

    function ROLE_MANAGER() external view returns (bytes32);

    function ROLE_PAUSER() external view returns (bytes32);

    function ROLE_UPGRADER() external view returns (bytes32);
}
