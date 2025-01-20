// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IERC721Enumerable} from "lib/forge-std/src/interfaces/IERC721.sol";

interface IynETH {
    function depositETH(address receiver) external payable returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);
    function unpauseDeposits() external;
}

contract VaultMainnetYnETHWithdrawerTest is Test, AssertUtils, MainnetActors {
        Withdrawer public withdrawer;
        WETH9 public weth;

        address public alice = address(0xa11c3);
        IWithdrawalQueueManager public withdrawalQueueManagerLsde;
        IWithdrawalQueueManager public withdrawalQueueManagerYneth;
    function setUp() public {
        SetupWithdrawer setup = new SetupWithdrawer();
        (withdrawer, weth) = setup.setup();

        withdrawalQueueManagerLsde = IWithdrawalQueueManager(payable(address(MC.YNLSDE_WM)));
        withdrawalQueueManagerYneth = IWithdrawalQueueManager(payable(address(MC.YNETH_WM)));

        vm.label(address(withdrawer), "Withdrawer");
        vm.label(address(withdrawalQueueManagerYneth), "WithdrawalQueueManagerYneth");
        vm.label(address(withdrawalQueueManagerLsde), "WithdrawalQueueManagerLsde");
        vm.label(address(MC.YNETH), "YnETH");
        vm.label(address(MC.YNLSDE), "YnLSDE");
        vm.label(address(MC.WETH), "WETH");
        vm.label(address(MC.YNETH_WM), "YnETH_WM");
        vm.label(address(MC.YNLSDE_WM), "YnLSDE_WM");

    }

    function processWithdrawalRequest(uint256 withdrawAmount) public returns (uint256 tokenId) {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = address(MC.YNETH);
        targets[1] = address(withdrawalQueueManagerYneth);

        values[0] = 0;
        values[1] = 0;
        
        data[0] = abi.encodeWithSelector(IynETH.approve.selector, MC.YNETH_WM, withdrawAmount);     
        bytes4 REQUEST_WITHDRAWAL_SELECTOR = bytes4(keccak256("requestWithdrawal(uint256)"));
        data[1] = abi.encodeWithSelector(REQUEST_WITHDRAWAL_SELECTOR, withdrawAmount);

        vm.startPrank(ADMIN);
        bytes[] memory returnData = withdrawer.processor(targets, values, data);
        vm.stopPrank();
        (uint256[] memory requests, ) = withdrawalQueueManagerYneth.withdrawalRequestsForOwner(address(withdrawer));
        assertEq(requests.length, 1);
        tokenId = abi.decode(returnData[1], (uint256));
    }

    function finalizeWithdrawalRequest(uint256 tokenId) public {
        // hardcoded mainnet request finalizer
        vm.prank(address(0x7f7187fbD6e508bC23268746dff535cfC8EbC87b));
        withdrawalQueueManagerYneth.finalizeRequestsUpToIndex(tokenId + 1);
    }

    function processWithdrawalClaim(uint256 tokenId, address receiver) public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(withdrawalQueueManagerYneth);
        values[0] = 0;
        bytes4 CLAIM_WITHDRAWAL_SELECTOR = bytes4(keccak256("claimWithdrawal(uint256,address)"));
        data[0] = abi.encodeWithSelector(CLAIM_WITHDRAWAL_SELECTOR, tokenId, receiver);

        vm.startPrank(ADMIN);
        withdrawer.processor(targets, values, data);
        vm.stopPrank();
    }

    function test_asyncWithdrawBalance() public {
        uint256 withdrawAmount = 10 ether;
        (uint256 withdrawBalance, uint256 baseBalance) = withdrawer.asyncWithdrawBalance(MC.YNETH);
        assertEq(withdrawBalance, 0);

        deal(MC.YNETH, address(withdrawer), 100 ether);
        deal(MC.YNETH, address(withdrawalQueueManagerYneth.redemptionAssetsVault()), 100 ether);

        uint256 tokenId = processWithdrawalRequest(withdrawAmount);
  

        uint256 fee = withdrawalQueueManagerYneth.withdrawalFee();
        uint256 expectedWithdrawBalance = (withdrawAmount * withdrawalQueueManagerYneth.redemptionAssetsVault().redemptionRate()) / 1e18 - ( withdrawAmount * fee / withdrawalQueueManagerYneth.FEE_PRECISION());

        (withdrawBalance, baseBalance) = withdrawer.asyncWithdrawBalance(MC.YNETH);
        
        assertEq(withdrawBalance, expectedWithdrawBalance);
        finalizeWithdrawalRequest(tokenId);
        uint256 finalizationId = withdrawalQueueManagerYneth.findFinalizationForTokenId(tokenId);
        assertGt(finalizationId, 0);
        uint256 availableRedemptionAssets = withdrawalQueueManagerYneth.redemptionAssetsVault().availableRedemptionAssets();
        assertGt(availableRedemptionAssets, withdrawAmount);
        processWithdrawalClaim(tokenId, ADMIN);

        (withdrawBalance,baseBalance) = withdrawer.asyncWithdrawBalance(MC.YNETH);
        assertEq(withdrawBalance, 0);
    }

    
}
