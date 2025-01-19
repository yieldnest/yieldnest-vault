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
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IProvider} from "src/interface/IProvider.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";

interface IAssetRegistry {
    function getAssets() external view returns (address[] memory);
}

interface IRAV {
    function redemptionRate() external view returns (uint256);
    function assetRegistry() external view returns (IAssetRegistry);
    function availableRedemptionAssets() external view returns (uint256);
    function deposit(uint256 amount, address asset) external;
}

contract WithdrawerMainnetTest is Test, AssertUtils, MainnetActors {
    using Math for uint256;

    Withdrawer public vault;

    uint256 public constant INITIAL_BALANCE = 100 ether;

    IProvider public provider = IProvider(MC.PROVIDER);

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 internal constant QUEUE_POSITION = keccak256("lido.WithdrawalQueue.queue");

    function _getWithdrawalRequestFromQueue(uint256 requestId)
        internal
        returns (IWithdrawalQueue.WithdrawalRequest memory request)
    {
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 slot = vm.getMappingSlotAt(address(MC.WSTETH_WQ), QUEUE_POSITION, requestId);
        uint256 requestSlot = uint256(slot);

        request = IWithdrawalQueue.WithdrawalRequest({
            cumulativeStETH: uint128(uint256(vm.load(address(MC.WSTETH_WQ), bytes32(requestSlot)))),
            cumulativeShares: uint128(uint256(vm.load(address(MC.WSTETH_WQ), bytes32(requestSlot + 1)))),
            owner: address(uint160(uint256(vm.load(address(MC.WSTETH_WQ), bytes32(requestSlot + 2))))),
            timestamp: uint40(uint256(vm.load(address(MC.WSTETH_WQ), bytes32(requestSlot + 3)))),
            claimed: vm.load(address(MC.WSTETH_WQ), bytes32(requestSlot + 4)) != bytes32(0),
            reportTimestamp: uint40(uint256(vm.load(address(MC.WSTETH_WQ), bytes32(requestSlot + 5))))
        });
    }

    function setUp() public {
        SetupWithdrawer setup = new SetupWithdrawer();
        vault = setup.setup();

        // setup some default balances for the vault
        deal(MC.WETH, address(vault), INITIAL_BALANCE);
        deal(MC.WSTETH, address(vault), INITIAL_BALANCE);
        deal(MC.WOETH, address(vault), INITIAL_BALANCE);
        deal(MC.YNETH, address(vault), INITIAL_BALANCE);
        deal(MC.YNLSDE, address(vault), INITIAL_BALANCE);

        // setup some default balances for withdrawal queue managers
        deal(MC.YNETH_RAV, INITIAL_BALANCE * 100);
        deal(MC.WSTETH_WQ, INITIAL_BALANCE * 100);

        address[] memory assets = IRAV(MC.YNLSDE_RAV).assetRegistry().getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            deal(assets[i], address(this), INITIAL_BALANCE * 100);
            IERC20(assets[i]).approve(MC.YNLSDE_RAV, INITIAL_BALANCE * 100);
            IRAV(MC.YNLSDE_RAV).deposit(INITIAL_BALANCE * 100, assets[i]);
        }

        // assert that the vault has some available assets
        assertGt(MC.WSTETH_WQ.balance, INITIAL_BALANCE, "wstETH withdrawal queue manager should have some balance");
        assertGt(
            IRAV(MC.YNLSDE_RAV).availableRedemptionAssets(),
            INITIAL_BALANCE,
            "ynLSDe redemption vault should have some available assets"
        );
        assertGt(
            IRAV(MC.YNETH_RAV).availableRedemptionAssets(),
            INITIAL_BALANCE,
            "ynETH redemption vault should have some available assets"
        );

        // grant finalizer role to the admin
        vm.startPrank(ADMIN);
        _grantFinalizerRole(MC.YNETH_WQM, ADMIN);
        _grantFinalizerRole(MC.YNLSDE_WQM, ADMIN);
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

    function test_Vault_views() public view {
        assertEq(vault.asset(), MC.WETH, "Asset address should match");

        uint256 totalAssets = INITIAL_BALANCE; // WETH
        totalAssets += _convertAssetToBase(MC.WSTETH, INITIAL_BALANCE); // WSTETH
        totalAssets += _convertAssetToBase(MC.WOETH, INITIAL_BALANCE); // WOETH
        totalAssets += _convertAssetToBase(MC.YNETH, INITIAL_BALANCE); // YNETH
        totalAssets += _convertAssetToBase(MC.YNLSDE, INITIAL_BALANCE); // YNLSDE

        assertEq(vault.totalAssets(), totalAssets, "Total assets should match");
    }

    function _requestWithdrawal(address asset_, address queueManager_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        IERC20 asset = IERC20(asset_);
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);

        (uint256 assets,) = vault.asyncWithdrawBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = vault.totalAssets();

        // TODO: replace with processor
        vm.startPrank(address(vault));
        asset.approve(address(queueManager), amount);
        tokenId = queueManager.requestWithdrawal(amount);
        vm.stopPrank();

        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        assertEq(request.amount, amount, "Amount should match");

        (assets,) = vault.asyncWithdrawBalance(asset_);

        assertApproxEqRel(assets, amount, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");
    }

    function test_Vault_RequestWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawal(MC.YNETH, MC.YNETH_WQM, amount);
    }

    function _claimWithdrawal(address asset_, address queueManager_, uint256 tokenId) internal {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        uint256 totalAssets = vault.totalAssets();

        vm.startPrank(ADMIN);
        queueManager.finalizeRequestsUpToIndex(tokenId + 1);
        vm.stopPrank();

        // TODO: replace with processor
        vm.startPrank(address(vault));
        queueManager.claimWithdrawal(tokenId, address(vault));
        vm.stopPrank();

        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        uint256 withdrawalFee = queueManager.withdrawalFee();
        uint256 amountInBase = _convertAssetToBase(asset_, request.amount);

        uint256 expectedFee = queueManager.calculateFee(amountInBase, withdrawalFee);

        assertApproxEqRel(vault.totalAssets(), totalAssets - expectedFee, 1e15, "Total assets should match");
    }

    function test_Vault_ClaimWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawal(MC.YNETH, MC.YNETH_WQM, amount);

        (uint256 assets,) = vault.asyncWithdrawBalance(MC.YNETH);
        assertApproxEqRel(assets, amount, 1e15, "Queued assets should match");

        _claimWithdrawal(MC.YNETH, MC.YNETH_WQM, tokenId);

        (assets,) = vault.asyncWithdrawBalance(MC.YNETH);
        assertEq(assets, 0, "Queued assets should match");
    }

    function test_Vault_RequestWithdrawal_YNLSDE(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawal(MC.YNLSDE, MC.YNLSDE_WQM, amount);
    }

    function test_Vault_ClaimWithdrawal_YNLSDE(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawal(MC.YNLSDE, MC.YNLSDE_WQM, amount);

        (uint256 assets,) = vault.asyncWithdrawBalance(MC.YNLSDE);
        assertApproxEqRel(assets, amount, 1e15, "Queued assets should match");

        uint256 rateFromProvider = provider.getRate(MC.YNLSDE);
        uint256 redemptionRate = IRAV(MC.YNLSDE_RAV).redemptionRate();

        assertEq(rateFromProvider, redemptionRate, "Rate from provider should match");

        _claimWithdrawal(MC.YNLSDE, MC.YNLSDE_WQM, tokenId);

        (assets,) = vault.asyncWithdrawBalance(MC.YNLSDE);
        assertEq(assets, 0, "Queued assets should match");
    }

    function test_Vault_RequestWithdrawal_WSTETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        address asset_ = MC.WSTETH;

        IERC20 asset = IERC20(asset_);
        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WQ);

        (uint256 assets,) = vault.asyncWithdrawBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = vault.totalAssets();

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // TODO: replace with processor
        vm.startPrank(address(vault));
        asset.approve(address(queue), amount);
        queue.requestWithdrawalsWstETH(amounts, address(vault));
        vm.stopPrank();

        (assets,) = vault.asyncWithdrawBalance(asset_);

        assertApproxEqRel(assets, amount, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");
    }

    function test_Vault_ClaimWithdrawal_WSTETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        address asset_ = MC.WSTETH;

        IERC20 asset = IERC20(asset_);
        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WQ);

        (uint256 assets,) = vault.asyncWithdrawBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = vault.totalAssets();

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // TODO: replace with processor
        vm.startPrank(address(vault));
        asset.approve(address(queue), amount);
        uint256[] memory tokenIds = queue.requestWithdrawalsWstETH(amounts, address(vault));
        vm.stopPrank();

        uint256 tokenId = tokenIds[0];

        (assets,) = vault.asyncWithdrawBalance(asset_);

        assertApproxEqRel(assets, amount, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(tokenIds);
        assertEq(statuses.length, 1, "Statuses length should match");

        uint256 shareRate = statuses[0].amountOfStETH * 1e27 / statuses[0].amountOfShares;

        uint256 lastFinalizedIndex = queue.getLastFinalizedRequestId();
        IWithdrawalQueue.WithdrawalRequest memory request = _getWithdrawalRequestFromQueue(tokenId);
        IWithdrawalQueue.WithdrawalRequest memory lastFinalizedRequest =
            _getWithdrawalRequestFromQueue(lastFinalizedIndex);
        uint256 amountOfEth = request.cumulativeStETH - lastFinalizedRequest.cumulativeStETH;

        deal(address(MC.STETH), amountOfEth);
        vm.startPrank(MC.STETH);
        queue.finalize{value: amountOfEth}(tokenId, shareRate);
        vm.stopPrank();

        // TODO: replace with processor
        vm.startPrank(address(vault));
        queue.claimWithdrawal(tokenId);
        vm.stopPrank();

        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");
    }
}
