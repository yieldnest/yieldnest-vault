/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IActors {
    function ADMIN() external view returns (address);
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
    address public constant ADMIN = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROCESSOR = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROPOSER_1 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROPOSER_2 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant EXECUTOR_1 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant EXECUTOR_2 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    address public constant FEE_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROVIDER_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant BUFFER_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant ASSET_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROCESSOR_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PAUSER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant UNPAUSER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
}

contract MainnetActors is IActors {
    address public constant ADMIN = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROCESSOR = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant EXECUTOR_1 = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROPOSER_1 = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant EXECUTOR_2 = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROPOSER_2 = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;

    address public constant FEE_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROVIDER_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant BUFFER_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant ASSET_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROCESSOR_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PAUSER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant UNPAUSER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
}
