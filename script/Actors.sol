/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IActors {
    function ADMIN() external view returns (address);
    function PROCESSOR() external view returns (address);
    function EXECUTOR_1() external view returns (address);
    function PROPOSER_1() external view returns (address);
}

contract HoleskyActors is IActors {
    address public constant ADMIN = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant PROCESSOR = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant EXECUTOR_1 = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant PROPOSER_1 = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;

    address public constant PROVIDER_MANAGER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant BUFFER_MANAGER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant ASSET_MANAGER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant PROCESSOR_MANAGER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant PAUSER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant UNPAUSER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;

    address public constant ALLOCATOR_MANAGER = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
}

contract MainnetActors is IActors {
    address public constant ADMIN = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROCESSOR = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant EXECUTOR_1 = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROPOSER_1 = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;

    address public constant PROVIDER_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant BUFFER_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant ASSET_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PROCESSOR_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant PAUSER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant UNPAUSER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant FEE_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;

    address public constant ALLOCATOR_MANAGER = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
}
