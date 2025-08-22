
// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IVault} from "src/interface/IVault.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";

library WithdrawerProcessorUtils {

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 internal constant QUEUE_POSITION = keccak256("lido.WithdrawalQueue.queue");

    function processRequestWithdrawalWstETH(IVault vault_, address asset_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        address[] memory targets = new address[](2);
        targets[0] = asset_;
        targets[1] = MC.WSTETH_WITHDRAWAL_QUEUE;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.WSTETH_WITHDRAWAL_QUEUE, amount);
        data[1] = abi.encodeWithSignature("requestWithdrawalsWstETH(uint256[],address)", amounts, address(vault_));

        bytes[] memory returnData = vault_.processor(targets, values, data);

        uint256[] memory tokenIds = abi.decode(returnData[1], (uint256[]));
        tokenId = tokenIds[0];
    }

    function processClaimWithdrawalWstETH(IVault vault_, uint256 tokenId) internal {
        address[] memory targets = new address[](1);
        targets[0] = MC.WSTETH_WITHDRAWAL_QUEUE;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("claimWithdrawal(uint256)", tokenId);

        vault_.processor(targets, values, data);
    }

    function claimWithdrawalWstETH(IVault vault_, address processor, uint256 tokenId) internal {

        Vm vm = Vm(CHEATCODE_ADDRESS);

        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        IWithdrawalQueue.WithdrawalRequestStatus memory status = getWithdrawalRequestStatusFromQueue(tokenId);
        uint256 shareRate = status.amountOfStETH * 1e27 / status.amountOfShares;

        uint256 lastFinalizedIndex = queue.getLastFinalizedRequestId();
        IWithdrawalQueue.WithdrawalRequest memory request = getWithdrawalRequestFromQueue(tokenId);
        IWithdrawalQueue.WithdrawalRequest memory lastFinalizedRequest =
            getWithdrawalRequestFromQueue(lastFinalizedIndex);
        uint256 amountOfEth = request.cumulativeStETH - lastFinalizedRequest.cumulativeStETH;

        vm.deal(address(MC.STETH), amountOfEth);
        vm.startPrank(MC.STETH);
        queue.finalize{value: amountOfEth}(tokenId, shareRate);
        vm.stopPrank();

        vm.startPrank(processor);
        processClaimWithdrawalWstETH(vault_, tokenId);
        vm.stopPrank();
    }

    function getWithdrawalRequestStatusFromQueue(uint256 tokenId)
        internal
        view
        returns (IWithdrawalQueue.WithdrawalRequestStatus memory)
    {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(tokenIds);

        return statuses[0];
    }

    function getWithdrawalRequestFromQueue(uint256 requestId)
        internal
        returns (IWithdrawalQueue.WithdrawalRequest memory request)
    {
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 slot = vm.getMappingSlotAt(address(MC.WSTETH_WITHDRAWAL_QUEUE), QUEUE_POSITION, requestId);
        uint256 requestSlot = uint256(slot);

        request = IWithdrawalQueue.WithdrawalRequest({
            cumulativeStETH: uint128(uint256(vm.load(address(MC.WSTETH_WITHDRAWAL_QUEUE), bytes32(requestSlot)))),
            cumulativeShares: uint128(uint256(vm.load(address(MC.WSTETH_WITHDRAWAL_QUEUE), bytes32(requestSlot + 1)))),
            owner: address(uint160(uint256(vm.load(address(MC.WSTETH_WITHDRAWAL_QUEUE), bytes32(requestSlot + 2))))),
            timestamp: uint40(uint256(vm.load(address(MC.WSTETH_WITHDRAWAL_QUEUE), bytes32(requestSlot + 3)))),
            claimed: vm.load(address(MC.WSTETH_WITHDRAWAL_QUEUE), bytes32(requestSlot + 4)) != bytes32(0),
            reportTimestamp: uint40(uint256(vm.load(address(MC.WSTETH_WITHDRAWAL_QUEUE), bytes32(requestSlot + 5))))
        });
    }

}