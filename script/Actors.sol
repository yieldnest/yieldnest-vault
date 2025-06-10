/* solhint-disable one-contract-per-file, const-name-snakecase */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IActors {
    function ADMIN() external view returns (address);
    function UNAUTHORIZED() external view returns (address);
    function PROPOSER_1() external view returns (address);
    function EXECUTOR_1() external view returns (address);

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
    /// @dev multisig
    function UPDATER() external view returns (address);
    /// @dev multisig
    function FEE_MANAGER() external view returns (address);

    /// @dev multisig
    function BOOTSTRAPPER() external view returns (address);

    function TIMELOCK() external view returns (address);
}

abstract contract LocalActors is IActors {
    address public constant ADMIN = address(1);
    address public constant PROCESSOR = address(2);
    address public constant EXECUTOR_1 = address(3);
    address public constant PROPOSER_1 = address(4);
    address public constant PROVIDER_MANAGER = address(5);
    address public constant BUFFER_MANAGER = address(6);
    address public constant ASSET_MANAGER = address(7);
    address public constant PROCESSOR_MANAGER = address(8);
    address public constant PAUSER = address(9);
    address public constant UNPAUSER = address(10);
    address public constant UPDATER = address(11);
    address public constant FEE_MANAGER = address(12);
    address public constant BOOTSTRAPPER = address(13);
    address public constant UNAUTHORIZED = address(0);
    address public constant TIMELOCK = address(14);
}

contract HoleskyActors is IActors {
    address public constant HoleskyAdmin = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;

    address public constant ADMIN = HoleskyAdmin;
    address public constant PROCESSOR = HoleskyAdmin;
    address public constant EXECUTOR_1 = HoleskyAdmin;
    address public constant PROPOSER_1 = HoleskyAdmin;
    address public constant PROVIDER_MANAGER = HoleskyAdmin;
    address public constant BUFFER_MANAGER = HoleskyAdmin;
    address public constant ASSET_MANAGER = HoleskyAdmin;
    address public constant PROCESSOR_MANAGER = HoleskyAdmin;
    address public constant PAUSER = HoleskyAdmin;
    address public constant UNPAUSER = HoleskyAdmin;
    address public constant ALLOCATOR_MANAGER = HoleskyAdmin;
    address public constant UPDATER = HoleskyAdmin;
    address public constant FEE_MANAGER = HoleskyAdmin;
    address public constant BOOTSTRAPPER = HoleskyAdmin;
    address public constant UNAUTHORIZED = address(0);
    address public constant TIMELOCK = HoleskyAdmin;
}

contract MainnetActors is IActors {
    address public constant YnSecurityCouncil = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant YnProcessor = 0x7e92AbC00F58Eb325C7fC95Ed52ACdf74584Be2c;
    address public constant YnDev = 0xa08F39d30dc865CC11a49b6e5cBd27630D6141C3;
    address public constant YnBootstrapper = 0x832e0D8e7A7Bdfe181f30df614383FAA4B5C2924;

    address public constant TIMELOCK = address(0x0);

    address public constant ADMIN = YnSecurityCouncil;
    address public constant PROCESSOR = YnProcessor;
    address public constant EXECUTOR_1 = YnSecurityCouncil;
    address public constant PROPOSER_1 = YnSecurityCouncil;

    address public constant PROVIDER_MANAGER = YnSecurityCouncil;
    address public constant BUFFER_MANAGER = YnSecurityCouncil;
    address public constant ASSET_MANAGER = YnSecurityCouncil;
    address public constant PROCESSOR_MANAGER = YnSecurityCouncil;
    address public constant PAUSER = YnDev;
    address public constant UNPAUSER = YnSecurityCouncil;
    address public constant FEE_MANAGER = YnSecurityCouncil;

    address public constant ALLOCATOR_MANAGER = YnSecurityCouncil;

    address public constant UPDATER = YnDev;
    // FIXME; set different bootstrapper for mainnet
    address public constant BOOTSTRAPPER = YnBootstrapper;
    address public constant UNAUTHORIZED = address(0);
}
