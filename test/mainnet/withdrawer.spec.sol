// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IERC20, Math} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IWithdrawalQueueManager, IRedemptionAssetsVault} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IProvider} from "src/interface/IProvider.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";

contract WithdrawerMainnetTest is Test, AssertUtils, MainnetActors, WithdrawerRules {
    using Math for uint256;

    Withdrawer public vault;
    uint256 public constant INITIAL_BALANCE = 100 ether;

    IProvider public provider;

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 internal constant QUEUE_POSITION = keccak256("lido.WithdrawalQueue.queue");

    function setUp() public {
        SetupWithdrawer setup = new SetupWithdrawer();
        vault = setup.setup();

        provider = IProvider(vault.provider());

        // NOTE: setup some default balances for the vault
        deal(MC.WETH, address(vault), INITIAL_BALANCE);
        deal(MC.WSTETH, address(vault), INITIAL_BALANCE);
        deal(MC.WOETH, address(vault), INITIAL_BALANCE);
        deal(MC.YNETH, address(vault), INITIAL_BALANCE);
        deal(MC.YNLSDE, address(vault), INITIAL_BALANCE);

        // NOTE: donate some assets to the queue managers / redemption assets vaults
        deal(MC.WSTETH_WITHDRAWAL_QUEUE, INITIAL_BALANCE * 100);
        deal(MC.YNETH_REDEMPTION_ASSETS_VAULT, INITIAL_BALANCE * 100);

        address[] memory assets = IRedemptionAssetsVault(MC.YNLSDE_REDEMPTION_ASSETS_VAULT).assetRegistry().getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            deal(assets[i], address(this), INITIAL_BALANCE * 100);
            IERC20(assets[i]).approve(MC.YNLSDE_REDEMPTION_ASSETS_VAULT, INITIAL_BALANCE * 100);
            IRedemptionAssetsVault(MC.YNLSDE_REDEMPTION_ASSETS_VAULT).deposit(INITIAL_BALANCE * 100, assets[i]);
        }

        assertGt(
            MC.WSTETH_WITHDRAWAL_QUEUE.balance,
            INITIAL_BALANCE,
            "wstETH withdrawal queue manager should have some balance"
        );
        assertGt(
            IRedemptionAssetsVault(MC.YNLSDE_REDEMPTION_ASSETS_VAULT).availableRedemptionAssets(),
            INITIAL_BALANCE,
            "ynLSDe redemption vault should have some available assets"
        );
        assertGt(
            IRedemptionAssetsVault(MC.YNETH_REDEMPTION_ASSETS_VAULT).availableRedemptionAssets(),
            INITIAL_BALANCE,
            "ynETH redemption vault should have some available assets"
        );

        // NOTE: grant finalizer role to the admin
        vm.startPrank(ADMIN);
        _grantFinalizerRole(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, ADMIN);
        _grantFinalizerRole(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, ADMIN);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        vault.grantRole(vault.PROCESSOR_ROLE(), address(this));
        vm.stopPrank();
    }

    function _grantFinalizerRole(address queueManager_, address finalizer_) internal {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        bytes32 finalizerRole = queueManager.REQUEST_FINALIZER_ROLE();

        AccessControl(queueManager_).grantRole(finalizerRole, finalizer_);
    }

    function _convertAssetToBase(address asset_, uint256 assets) internal view returns (uint256) {
        uint256 rate = provider.getRate(asset_);
        return assets.mulDiv(rate, 10 ** 18, Math.Rounding.Floor);
    }

    function _convertBaseToAsset(address asset_, uint256 assets) internal view returns (uint256) {
        uint256 rate = provider.getRate(asset_);
        return assets.mulDiv(10 ** 18, rate, Math.Rounding.Floor);
    }

    function test_Vault_views() public {
        assertEq(vault.asset(), MC.WETH, "Asset address should match");

        uint256 totalAssets = INITIAL_BALANCE; // WETH
        totalAssets += _convertAssetToBase(MC.WSTETH, INITIAL_BALANCE); // WSTETH
        totalAssets += _convertAssetToBase(MC.WOETH, INITIAL_BALANCE); // WOETH
        totalAssets += _convertAssetToBase(MC.YNETH, INITIAL_BALANCE); // YNETH
        totalAssets += _convertAssetToBase(MC.YNLSDE, INITIAL_BALANCE); // YNLSDE
        vault.processAccounting();
        assertEq(vault.totalAssets(), totalAssets, "Total assets should match");
    }

    function test_Vault_RequestWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawal(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, amount);
    }

    function test_Vault_ClaimWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawal(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, amount);

        _claimWithdrawal(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, tokenId);
    }

    function test_Vault_RequestWithdrawal_YNLSDE(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawal(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, amount);
    }

    function test_Vault_ClaimWithdrawal_YNLSDE(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawal(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, amount);

        _claimWithdrawal(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, tokenId);
    }

    function test_Vault_RequestWithdrawal_WSTETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawalWstETH(amount);
    }

    function test_Vault_ClaimWithdrawal_WSTETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawalWstETH(amount);

        _claimWithdrawalWstETH(tokenId);
    }

    function test_Vault_RequestWithdrawal_WOETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawalWOETH(amount);
    }

    function test_Vault_ClaimWithdrawal_WOETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawalWOETH(amount);

        _claimWithdrawalWOETH(tokenId);
    }

    /*
    // TODO: fix OETH tests
    // deal(MC.OETH, address(vault), INITIAL_BALANCE) fails
    function test_Vault_RequestWithdrawal_OETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawalOETH(amount);
    }

    function test_Vault_ClaimWithdrawal_OETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawalOETH(amount);

        _claimWithdrawalWOETH(tokenId);
    }

    function _requestWithdrawalOETH(uint256 amount) internal returns (uint256 tokenId) {
        address asset_ = MC.OETH;
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = vault.totalAssets();

        tokenId = vault.requestWithdrawalOETH(amount);

        IOETHVault.WithdrawalRequest memory request = oethVault.withdrawalRequests(tokenId);

        uint256 amountInBase = _convertAssetToBase(asset_, amount);
        assertApproxEqRel(request.amount, amountInBase, 1e15, "Amount should match");

        assets = vault.asyncWithdrawalBalance(asset_);
        assertApproxEqRel(assets, amountInBase, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");

        uint256[] memory requestIds = vault.getWOETHRequestIds();
        assertEq(requestIds.length, 1, "Request ids should match");
        assertEq(requestIds[0], tokenId, "Request ids should match");
    }
    */

    function _requestWithdrawalWOETH(uint256 amount) internal returns (uint256 tokenId) {
        address asset_ = MC.WOETH;
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = vault.totalAssets();

        tokenId = vault.requestWithdrawalWOETH(amount);

        IOETHVault.WithdrawalRequest memory request = oethVault.withdrawalRequests(tokenId);

        uint256 amountInBase = _convertAssetToBase(asset_, amount);
        assertApproxEqRel(request.amount, amountInBase, 1e15, "Amount should match");

        assets = vault.asyncWithdrawalBalance(asset_);
        assertApproxEqRel(assets, amountInBase, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");

        uint256[] memory requestIds = vault.getWOETHRequestIds();
        assertEq(requestIds.length, 1, "Request ids should match");
        assertEq(requestIds[0], tokenId, "Request ids should match");
    }

    function _claimWithdrawalWOETH(uint256 tokenId) internal {
        address asset_ = MC.WOETH;
        IERC20 weth = IERC20(MC.WETH);
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);
        uint256 totalAssets = vault.totalAssets();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        IOETHVault.WithdrawalQueueMetadata memory queue = oethVault.withdrawalQueueMetadata();
        uint256 outstandingWithdrawals = queue.queued - queue.claimed;
        deal(MC.WETH, MC.OETH_VAULT, outstandingWithdrawals + INITIAL_BALANCE);

        assertEq(weth.balanceOf(MC.OETH_VAULT), INITIAL_BALANCE + outstandingWithdrawals, "WETH balance should match");

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + oethVault.CLAIM_DELAY() + 10 minutes);

        vault.claimWithdrawalsWOETH(tokenIds);

        assertApproxEqRel(vault.totalAssets(), totalAssets, 2e15, "Total assets should match");

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should match");

        uint256[] memory requestIds = vault.getWOETHRequestIds();
        assertEq(requestIds.length, 0, "Request ids should match");

        vm.warp(timestamp);
    }

    function _requestWithdrawalWstETH(uint256 amount) internal returns (uint256 tokenId) {
        address asset_ = MC.WSTETH;
        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = vault.totalAssets();

        tokenId = processRequestWithdrawalWstETH(vault, MC.WSTETH_WITHDRAWAL_QUEUE, asset_, amount);

        IWithdrawalQueue.WithdrawalRequestStatus memory status = _getWithdrawalRequestStatusFromQueue(tokenId);

        assertApproxEqRel(status.amountOfShares, amount, 1e15, "Amount should match");

        assets = vault.asyncWithdrawalBalance(asset_);
        uint256 amountInBase = _convertAssetToBase(asset_, amount);

        assertApproxEqRel(assets, amountInBase, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");
    }

    function _getWithdrawalRequestStatusFromQueue(uint256 tokenId)
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

    function _claimWithdrawalWstETH(uint256 tokenId) internal {
        address asset_ = MC.WSTETH;
        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);
        uint256 totalAssets = vault.totalAssets();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        IWithdrawalQueue.WithdrawalRequestStatus memory status = _getWithdrawalRequestStatusFromQueue(tokenId);
        uint256 shareRate = status.amountOfStETH * 1e27 / status.amountOfShares;

        uint256 lastFinalizedIndex = queue.getLastFinalizedRequestId();
        IWithdrawalQueue.WithdrawalRequest memory request = _getWithdrawalRequestFromQueue(tokenId);
        IWithdrawalQueue.WithdrawalRequest memory lastFinalizedRequest =
            _getWithdrawalRequestFromQueue(lastFinalizedIndex);
        uint256 amountOfEth = request.cumulativeStETH - lastFinalizedRequest.cumulativeStETH;

        deal(address(MC.STETH), amountOfEth);
        vm.startPrank(MC.STETH);
        queue.finalize{value: amountOfEth}(tokenId, shareRate);
        vm.stopPrank();

        processClaimWithdrawalWstETH(vault, MC.WSTETH_WITHDRAWAL_QUEUE, tokenId);

        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should match");
    }

    function _requestWithdrawal(address asset_, address queueManager_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        vault.processAccounting();
        uint256 totalAssets = vault.totalAssets();

        tokenId = processRequestWithdrawal(vault, queueManager_, asset_, amount);

        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        assertEq(request.amount, amount, "Amount should match");

        assets = vault.asyncWithdrawalBalance(asset_);
        uint256 amountInBase = _convertAssetToBase(asset_, amount);

        assertApproxEqRel(assets, amountInBase, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");
    }

    function _claimWithdrawal(address asset_, address queueManager_, uint256 tokenId) internal {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        vault.processAccounting();
        uint256 totalAssets = vault.totalAssets();

        vm.startPrank(ADMIN);
        queueManager.finalizeRequestsUpToIndex(tokenId + 1);
        vm.stopPrank();

        processClaimWithdrawal(vault, queueManager_, tokenId);
        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        uint256 amountInBase = _convertAssetToBase(asset_, request.amount);

        uint256 expectedFee = queueManager.calculateFee(amountInBase, request.feeAtRequestTime);
        assertApproxEqRel(vault.totalAssets(), totalAssets - expectedFee, 1e15, "Total assets should match");

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should match");
    }

    function _getWithdrawalRequestFromQueue(uint256 requestId)
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
