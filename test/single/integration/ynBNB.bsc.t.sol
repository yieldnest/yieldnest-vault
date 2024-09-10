// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { BscContracts } from "script/Contracts.sol";
import { BscActors } from "script/Actors.sol";
import { VaultFactory } from "src/VaultFactory.sol";
import { SingleVault } from "src/SingleVault.sol";
import { ynBNBConstants } from "script/Constants.sol";
import { IERC20, IERC4626 } from "src/Common.sol";
import { AssetHelper } from "test/helpers/Assets.sol";

import "lib/forge-std/src/Test.sol";

interface IKarakVaultSupervisor {
    function deposit(address vault,uint256 amount,uint256 minSharesOut) external;
}


contract KslisBNB_Test is Test, BscActors, BscContracts, ynBNBConstants, AssetHelper {
    VaultFactory public factory;
    SingleVault public ynBNB;
    IERC20 public slis;
    IERC4626 kslis = IERC4626(KARAK_KslisBNB);
    IKarakVaultSupervisor ksup = IKarakVaultSupervisor(KARAK_VAULT_SUPERVISOR);

    address USER = 0x0c099101d43e9094E4ae9bC2FC38f8b9875c23c5;

    modifier onlyBsc() {
        if (block.chainid != 56) return;
        _;
    }


    function setUp() onlyBsc public {
        slis = IERC20(slisBNB);
        get_slisBNB(address(this), 10_000 ether);
        factory = VaultFactory(address(VAULT_FACTORY));
        slis.approve(address(factory), 1 ether);
        slis.transfer(address(factory), 1 ether);

        address[] memory proposers = new address[](2);
        proposers[0] = PROPOSER_1;
        proposers[1] = PROPOSER_2;

        address[] memory executors = new address[](2);
        executors[0] = EXECUTOR_1;
        executors[1] = EXECUTOR_2;

        vm.startPrank(ADMIN);
        address vaultAddress = factory.createSingleVault(
            IERC20(slisBNB),
            VAULT_NAME,
            VAULT_SYMBOL,
            ADMIN,
            MIN_DELAY,
            proposers,
            executors
        );
        ynBNB = SingleVault(payable(vaultAddress));
        assertEq(ynBNB.symbol(), VAULT_SYMBOL);
        vm.stopPrank();
    }

    function depositForUser(address user, uint256 amount) public returns (uint256 shares) {
        slis.approve(user, amount);
        slis.transfer(user, amount);

        vm.startPrank(user);
        slis.approve(address(ynBNB), amount);
        shares = ynBNB.deposit(amount, user);

        assertEq(ynBNB.totalSupply(), shares + 1 ether);
        assertEq(ynBNB.totalAssets(), shares + 1 ether);
        vm.stopPrank();
    }

    function withdrawForUser(address user, uint256 amount) public returns (uint256 shares) {
        vm.startPrank(user);

        uint256 previousTotalSupply = ynBNB.totalSupply();
        uint256 previousTotalAssets = ynBNB.totalAssets();
        uint256 userMaxWithdraw = ynBNB.previewWithdraw(amount);

        shares = ynBNB.withdraw(userMaxWithdraw, user, user);

        assertEq(ynBNB.totalSupply(), previousTotalSupply - shares);
        assertEq(ynBNB.totalAssets(), previousTotalAssets - shares);
        vm.stopPrank();
    }

    function test_ynBNB_deposit_withdraw() onlyBsc public {
        depositForUser(USER, 3 ether);
        withdrawForUser(USER, 3 ether);
    }

    function test_KslisBNB_deposit() onlyBsc public {
        slis.transfer(USER, 1 ether);
        vm.startPrank(USER);
        slis.approve(address(kslis), 1 ether);
        ksup.deposit(address(kslis), 1 ether, 1 ether);
    }
}