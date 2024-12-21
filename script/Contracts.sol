/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function WBNB() external view returns (address);
    function SLISBNB() external view returns (address);
    function BNBX() external view returns (address);

    function YNWBNBK() external view returns (address);
    function YNBNBK() external view returns (address);
    function YNCLISBNBK() external view returns (address);
}

library MainnetContracts {
    // tokens
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant SLISBNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant BNBX = 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275;

    // stake managers
    address public constant BNBX_STAKE_MANAGER = 0x3b961e83400D51e6E1AF5c450d3C7d7b80588d28;
    address public constant SLIS_BNB_STAKE_MANAGER = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;

    // TODO: fix the ynwbnbk and ynclisbnbk addresses
    // bnb vault
    address public constant YNBNBK = 0x304B5845b9114182ECb4495Be4C91a273b74B509;
    address public constant YNWBNBK = address(0);
    address public constant YNCLISBNBK = address(0);

    address public constant PROVIDER = address(123456789); // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer

    //// UNIT TEST ONLY references ////
    address public constant WETH = WBNB;
    address public constant STETH = SLISBNB;
    address public constant RETH = BNBX;

    address public constant YNETH = YNBNBK;
}

library TestnetContracts {
    // tokens
    address public constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address public constant SLISBNB = 0xCc752dC4ae72386986d011c2B485be0DAd98C744;
    address public constant BNBX = 0x6cd3f51A92d022030d6e75760200c051caA7152A;

    // TODO: fix the ynwbnbk and ynclisbnbk addresses
    // bnb vault
    address public constant YNBNBK = 0x7e87787C22117374Fad2E3E2E8C6159f0875F92e;
    address public constant YNWBNBK = address(0);
    address public constant YNCLISBNBK = address(0);

    address public constant PROVIDER = address(123456789);
    address public constant BUFFER = address(987654321);
}

contract ChapelContracts is IContracts {
    function WBNB() external pure override returns (address) {
        return TestnetContracts.WBNB;
    }

    function SLISBNB() external pure override returns (address) {
        return TestnetContracts.SLISBNB;
    }

    function BNBX() external pure override returns (address) {
        return TestnetContracts.BNBX;
    }

    function YNBNBK() external pure override returns (address) {
        return TestnetContracts.YNBNBK;
    }

    function YNWBNBK() external pure override returns (address) {
        return TestnetContracts.YNWBNBK;
    }

    function YNCLISBNBK() external pure override returns (address) {
        return TestnetContracts.YNCLISBNBK;
    }
}

contract BscContracts is IContracts {
    function WBNB() external pure override returns (address) {
        return MainnetContracts.WBNB;
    }

    function SLISBNB() external pure override returns (address) {
        return MainnetContracts.SLISBNB;
    }

    function BNBX() external pure override returns (address) {
        return MainnetContracts.BNBX;
    }

    function YNBNBK() external pure override returns (address) {
        return MainnetContracts.YNBNBK;
    }

    function YNWBNBK() external pure override returns (address) {
        return MainnetContracts.YNWBNBK;
    }

    function YNCLISBNBK() external pure override returns (address) {
        return MainnetContracts.YNCLISBNBK;
    }
}
