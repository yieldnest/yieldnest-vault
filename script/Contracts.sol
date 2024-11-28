// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

library MainnetContracts {

    address public constant BNBX = 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275;
    address public constant SLISBNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant BNBX_STAKE_MANAGER = 0x3b961e83400D51e6E1AF5c450d3C7d7b80588d28;
    address public constant SLIS_BNB_STAKE_MANAGER = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    
    address public constant YNBNBk = 0x304B5845b9114182ECb4495Be4C91a273b74B509;


    // TODO: update to Binance Mainnet values
    address public constant CL_STETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address public constant TIMELOCK = 0xb5b52c63067E490982874B0d0F559668Bbe0c36B;
    address public constant FACTORY = 0x1756987c66eC529be59D3Ec1edFB005a2F9728E1;
    address public constant PROXY_ADMIN = 0xA02A8DC24171aC161cCb74Ef02C28e3cA2204783;

    address public constant PROVIDER = address(123456789); // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer

    //// UNIT TEST ONLY references ////
    address public constant WETH = WBNB;
    address public constant STETH = SLISBNB;
    address public constant RETH = BNBX;

    address public constant YNETH = YNBNBk;
}
