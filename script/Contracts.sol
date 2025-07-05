/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function USDC() external pure returns (address);
}

library MainnetContracts {
    address public constant PROVIDER = address(123456789); // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer

    // RWA
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant YNRWAX = 0x01Ba69727E2860b37bc1a2bd56999c1aFb4C15D8;
    address public constant YNRWAX_VIEWER = 0x0F2b81368781f1c846c8B2ad48BaCB45a0bea74e;
    address public constant X_REFERRAL_ADAPTER = 0xdb7aa02Ee83fdE44b5F8bC24Bb1206C1898E3fC0;
    address public constant WUSDC = 0xdA7d2025c7f1f1A1d34AB3F4dF01102d0428E574;

    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    address public constant FLEX_STRATEGY_USDC = address(0xf1ec);
}

contract L1Contracts is IContracts {
    function USDC() external pure override returns (address) {
        return MainnetContracts.USDC;
    }
}
