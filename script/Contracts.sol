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
    function YNASBNBK() external view returns (address);

    function YNBNBX() external view returns (address);
    function TIMELOCK() external view returns (address);
    function CLIS_BNB_STRATEGY() external view returns (address);
}

library MainnetContracts {
    // tokens
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant SLISBNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant BNBX = 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275;
    address public constant CLISBNB = 0x4b30fcAA7945fE9fDEFD2895aae539ba102Ed6F6;
    address public constant ASBNB = 0x77734e70b6E88b4d82fE632a168EDf6e700912b6;

    // stake managers
    address public constant BNBX_STAKE_MANAGER = 0x3b961e83400D51e6E1AF5c450d3C7d7b80588d28;
    address public constant SLIS_BNB_STAKE_HUB = 0x0000000000000000000000000000000000002002;
    address public constant SLIS_BNB_STAKE_MANAGER = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address public constant AS_BNB_MINTER = 0x2F31ab8950c50080E77999fa456372f276952fD8;

    // max vault
    address public constant YNBNBX = 0x32C830f5c34122C6afB8aE87ABA541B7900a2C5F;
    address public constant TIMELOCK = 0x2F3fEdd2F6EC681D9Cc2ecC688d8C7286Eca1F40;

    // bnb vault
    address public constant YNBNBK = 0x304B5845b9114182ECb4495Be4C91a273b74B509;
    address public constant YNWBNBK = 0x6EC6b7F106674d6D82b7b24446C7ebaf349d59A1;
    address public constant YNCLISBNBK = 0x03276919F8b6eE37BA8EE4ee68a1c5f48b667834;
    address public constant YNASBNBK = 0x504A89a3Ed6A51D17D4f936E58476c779EE7315b;

    address public constant PROVIDER = address(0x0d); // TODO: Update with deployed Provider
    address public constant BUFFER = 0x6EC6b7F106674d6D82b7b24446C7ebaf349d59A1;

    // kernel
    address public constant STAKER_GATEWAY = 0xb32dF5B33dBCCA60437EC17b27842c12bFE83394;
    address public constant KERNEL_CONFIG = 0x45d7Bb73253A908E6160aa5FD9DA083F7Bc6faf5;
    address public constant KERNEL_CONFIG_ADMIN = 0x40f5f0f5E78289B33E450fBCA1cbD8700098cd23;

    //// UNIT TEST ONLY references ////
    address public constant WETH = WBNB;
    address public constant STETH = SLISBNB;
    address public constant RETH = BNBX;

    address public constant YNETH = YNBNBK;
    address public constant CLIS_BNB_STRATEGY = address(0x0c); // TODO: update with deployed strategy
}

library TestnetContracts {
    // tokens
    address public constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address public constant SLISBNB = 0xCc752dC4ae72386986d011c2B485be0DAd98C744;
    address public constant BNBX = 0x6cd3f51A92d022030d6e75760200c051caA7152A;

    address public constant YNBNBX = 0x6164f96Fa28147508d3545c38B61eD0BD7c5DF03;
    address public constant TIMELOCK = 0x0672980063d35393084989754f14f7E90F4AB3aD;

    // bnb vault
    address public constant YNBNBK = 0x7e87787C22117374Fad2E3E2E8C6159f0875F92e;
    address public constant YNWBNBK = 0xAe35b540eFC98c7866A983eaB3B88a0a47614CA1;
    address public constant YNCLISBNBK = address(0x0c); // NOTE: not supported on testnet
    address public constant YNASBNBK = address(0x0a); // NOTE: not supported on testnet

    address public constant PROVIDER = address(0x0d); // TODO: Update with deployed Provider
    address public constant BUFFER = YNWBNBK;

    address public constant SLIS_BNB_STAKE_MANAGER = 0xc695F964011a5a1024931E2AF0116afBaC41B31B;
    address public constant CLIS_BNB_STRATEGY = 0xAD5214565030904E70b09Ef8936e2Fc26F8e9c77;
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

    function YNASBNBK() external pure override returns (address) {
        return TestnetContracts.YNASBNBK;
    }

    function YNBNBX() external pure override returns (address) {
        return TestnetContracts.YNBNBX;
    }

    function TIMELOCK() external pure override returns (address) {
        return TestnetContracts.TIMELOCK;
    }

    function CLIS_BNB_STRATEGY() external pure override returns (address) {
        return TestnetContracts.CLIS_BNB_STRATEGY;
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

    function YNASBNBK() external pure override returns (address) {
        return MainnetContracts.YNASBNBK;
    }

    function YNBNBX() external pure override returns (address) {
        return MainnetContracts.YNBNBX;
    }

    function TIMELOCK() external pure override returns (address) {
        return MainnetContracts.TIMELOCK;
    }

    function CLIS_BNB_STRATEGY() external pure override returns (address) {
        return MainnetContracts.CLIS_BNB_STRATEGY;
    }
}
