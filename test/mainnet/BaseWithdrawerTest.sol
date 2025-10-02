// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IERC20, Math} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IWithdrawalQueueManager, IRedemptionAssetsVault} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IProvider} from "src/interface/IProvider.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {WithdrawerProcessorUtils} from "test/utils/WithdrawerProcessorUtils.sol";
import {IAccessControl} from "src/Common.sol";

/**
 * @notice Tests for the Withdrawer contract
 *
 * This test suite verifies the Withdrawer contract's functionality in isolation with a fresh deployment.
 * Unlike other test suites that test integration with the main vault, these tests focus solely on the
 * Withdrawer contract's core withdrawal functionality. By testing in isolation, we can verify the
 * withdrawal logic works correctly without any dependencies on the main vault's state or behavior.
 *
 */
abstract contract BaseWithdrawerMainnetTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    Withdrawer public withdrawer;
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    IProvider public provider;

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 internal constant QUEUE_POSITION = keccak256("lido.WithdrawalQueue.queue");

    function getWithdrawer() public virtual returns (Withdrawer);

    function setUp() public override {
        super.setUp();

        withdrawer = getWithdrawer();

        provider = IProvider(withdrawer.provider());

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
        withdrawer.grantRole(withdrawer.PROCESSOR_ROLE(), address(this));
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

    function test_Vault_RequestWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        _requestWithdrawal(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, amount);
    }

    function test_Vault_ClaimWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        uint256 tokenId = _requestWithdrawal(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, amount);

        _claimWithdrawal(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, tokenId);
    }

    function test_Vault_RequestWithdrawal_YNLSDE(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        _requestWithdrawal(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, amount);
    }

    function test_Vault_ClaimWithdrawal_YNLSDE(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        uint256 tokenId = _requestWithdrawal(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, amount);

        _claimWithdrawal(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, tokenId);
    }

    function test_Vault_RequestWithdrawal_WSTETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < 1e3 ether);

        _requestWithdrawalWstETH(amount);
    }

    function test_Withdrawer_views() public view {
        assertTrue(withdrawer.getHasAllocator(), "Withdrawer should have allocators");
        assertTrue(withdrawer.getAssetWithdrawable(MC.WETH), "Withdrawer should have WETH withdrawable");
        assertEq(withdrawer.asset(), MC.WETH, "Withdrawer should have WETH as the main asset");
        assertFalse(withdrawer.alwaysComputeTotalAssets(), "Withdrawer should not always compute total assets");
        assertTrue(withdrawer.countNativeAsset(), "Withdrawer should not count native asset");
        assertEq(withdrawer.defaultAssetIndex(), 0, "Withdrawer should have WETH as the default asset");
        assertEq(withdrawer.decimals(), 18, "Withdrawer should have 18 decimals");
    }

    function test_Vault_ClaimWithdrawal_WSTETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < 1e3 ether);

        withdrawer.processAccounting();
        vault.processAccounting();
        uint256 initialAsyncBalance = withdrawer.asyncWithdrawalBalance(MC.WSTETH);

        uint256 tokenId = _requestWithdrawalWstETH(amount);

        uint256 totalAssets = withdrawer.totalAssets();
        WithdrawerProcessorUtils.claimWithdrawalWstETH(withdrawer, PROCESSOR, tokenId);

        withdrawer.processAccounting();
        vault.processAccounting();

        totalAssetsInvariant(totalAssets);

        uint256 assets = withdrawer.asyncWithdrawalBalance(MC.WSTETH);
        assertEq(assets, initialAsyncBalance, "Async withdrawal balance should be back to initial value after claim");
    }

    function test_Vault_RequestWithdrawal_WOETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        _requestWithdrawalWOETH(amount);
    }

    function test_Vault_ClaimWithdrawal_WOETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        uint256 tokenId = _requestWithdrawalWOETH(amount);

        _claimWithdrawalWOETH(tokenId);
    }

    function test_Vault_RequestWithdrawal_OETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        _requestWithdrawalOETH(amount);
    }

    function test_Vault_ClaimWithdrawal_OETH(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < INITIAL_BALANCE);

        uint256 tokenId = _requestWithdrawalOETH(amount);

        _claimWithdrawalWOETH(tokenId);
    }

    function test_withdrawer_arbitrary_address_deposit_reverts() public {
        address arbitraryUser = makeAddr("arbitraryUser");
        deal(MC.WETH, arbitraryUser, 1e18);
        vm.startPrank(arbitraryUser);
        IERC20(MC.WETH).approve(address(withdrawer), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(arbitraryUser),
                withdrawer.ALLOCATOR_ROLE()
            )
        );
        withdrawer.depositAsset(MC.WETH, 1e18, arbitraryUser);
        vm.stopPrank();
    }

    function _mintOETH(IVault vault_, uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.OETH_VAULT;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.OETH_VAULT, amount);
        data[1] = abi.encodeWithSignature("mint(address,uint256,uint256)", MC.WETH, amount, amount);

        vault_.processor(targets, values, data);
    }

    function _donate_single_asset(address asset, uint256 amount) internal returns (uint256) {
        address alice = address(0xa11ce);

        assertEq(IERC20(asset).balanceOf(alice), 0, "Balance should be 0 before donation");
        // assertLt(withdrawer.totalAssets(), 3, "Total assets should be zero initially");

        dealAsset(asset, alice, amount);

        // The donation function does not donate the full amount. Must use the actual donated amount after.
        uint256 donatedAmount = IERC20(asset).balanceOf(alice);

        // transfer donated amount to vault
        vm.startPrank(alice);
        IERC20(asset).transfer(address(withdrawer), donatedAmount);
        vm.stopPrank();

        withdrawer.processAccounting();

        assertGt(donatedAmount, 0, "Asset balance should be greater than zero");

        return donatedAmount;
    }

    function _requestWithdrawalOETH(uint256 amount) internal returns (uint256 tokenId) {
        vm.expectRevert(OriginWithdrawalLib.NotEnoughBalance.selector);
        withdrawer.requestWithdrawalOETH(amount);
        amount = _donate_single_asset(MC.OETH, amount);

        address asset_ = MC.OETH;
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256 assets = withdrawer.asyncWithdrawalBalance(MC.WOETH); // check WOETH balance for OETH
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = withdrawer.totalAssets();

        tokenId = withdrawer.requestWithdrawalOETH(amount);

        IOETHVault.WithdrawalRequest memory request = oethVault.withdrawalRequests(tokenId);

        uint256 amountInBase = _convertAssetToBase(asset_, amount);
        assertEq(amountInBase, amount, "Amount should match base amount for OETH");

        assertEq(request.amount, amountInBase, "Request amount should match");

        assets = withdrawer.asyncWithdrawalBalance(MC.WOETH); // check WOETH balance for OETH
        assertApproxEqAbs(assets, amountInBase, 3, "Queued assets should match");
        totalAssetsInvariant(totalAssets);

        uint256[] memory requestIds = withdrawer.getWOETHRequestIds();
        assertEq(requestIds.length, 1, "Request ids should match");
        assertEq(requestIds[0], tokenId, "Request ids should match");
    }

    function _requestWithdrawalWOETH(uint256 amount) internal returns (uint256 tokenId) {
        if (IERC20(MC.WOETH).balanceOf(address(withdrawer)) == 0) {
            vm.expectRevert(OriginWithdrawalLib.NotEnoughBalance.selector);
            withdrawer.requestWithdrawalWOETH(amount);
        }

        uint256 donatedAmount = _donate_single_asset(MC.WOETH, amount);

        address asset_ = MC.WOETH;
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256 assets = withdrawer.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        uint256 totalAssets = withdrawer.totalAssets();

        uint256[] memory requestIdsBefore = withdrawer.getWOETHRequestIds();

        tokenId = withdrawer.requestWithdrawalWOETH(donatedAmount);

        IOETHVault.WithdrawalRequest memory request = oethVault.withdrawalRequests(tokenId);

        uint256 amountInBase = amount;
        assertApproxEqAbs(request.amount, amountInBase + assets, 3, "Amount should match");

        assets = withdrawer.asyncWithdrawalBalance(asset_);
        assertApproxEqAbs(assets, amountInBase, 3, "Queued assets should match");
        totalAssetsInvariant(totalAssets);

        uint256[] memory requestIds = withdrawer.getWOETHRequestIds();
        assertEq(requestIds.length, requestIdsBefore.length + 1, "Request ids should increase by 1");
        assertEq(requestIds[requestIds.length - 1], tokenId, "Request ids should match for the new request");
    }

    function _claimWithdrawalWOETH(uint256 tokenId) internal {
        address asset_ = MC.WOETH;
        IERC20 weth = IERC20(MC.WETH);
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);
        uint256 totalAssets = withdrawer.totalAssets();

        vm.startPrank(oethVault.governor());
        oethVault.setMaxSupplyDiff(0);
        vm.stopPrank();

        IOETHVault.WithdrawalQueueMetadata memory queue = oethVault.withdrawalQueueMetadata();
        uint256 outstandingWithdrawals = queue.queued - queue.claimed;
        deal(MC.WETH, MC.OETH_VAULT, outstandingWithdrawals + INITIAL_BALANCE);

        assertEq(weth.balanceOf(MC.OETH_VAULT), INITIAL_BALANCE + outstandingWithdrawals, "WETH balance should match");

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + oethVault.withdrawalClaimDelay() + 10 minutes);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        withdrawer.claimWithdrawalsWOETH(tokenIds);

        totalAssetsInvariant(totalAssets);

        uint256 assets = withdrawer.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should match");

        uint256[] memory requestIds = withdrawer.getWOETHRequestIds();
        assertEq(requestIds.length, 0, "Request ids should match");

        vm.warp(timestamp);
    }

    function _requestWithdrawalWstETH(uint256 amount) internal returns (uint256 tokenId) {
        uint256 donatedAmount = _donate_single_asset(MC.WSTETH, amount);

        address asset_ = MC.WSTETH;
        uint256 initialAsyncBalance = withdrawer.asyncWithdrawalBalance(asset_);
        uint256 totalAssets = withdrawer.totalAssets();

        tokenId = WithdrawerProcessorUtils.processRequestWithdrawalWstETH(withdrawer, asset_, donatedAmount);

        IWithdrawalQueue.WithdrawalRequestStatus memory status =
            WithdrawerProcessorUtils.getWithdrawalRequestStatusFromQueue(tokenId);

        assertApproxEqAbs(status.amountOfShares, donatedAmount, 3, "Amount should match");

        uint256 asyncWithdrawalBalanceAfter = withdrawer.asyncWithdrawalBalance(asset_);
        uint256 amountInBase = amount;

        assertApproxEqAbs(
            asyncWithdrawalBalanceAfter - initialAsyncBalance, amountInBase, 3, "Queued assets should match"
        );
        totalAssetsInvariant(totalAssets);
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

    function _requestWithdrawal(address asset_, address queueManager_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        uint256 donatedAmount = _donate_single_asset(asset_, amount);

        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);

        uint256 assetsBefore = withdrawer.asyncWithdrawalBalance(asset_);
        withdrawer.processAccounting();
        uint256 totalAssets = withdrawer.totalAssets();

        tokenId = _processRequestWithdrawal(withdrawer, queueManager_, asset_, donatedAmount);

        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        assertEq(request.amount, donatedAmount, "Amount should match");

        uint256 assetsAfter = withdrawer.asyncWithdrawalBalance(asset_);
        uint256 baseAmount = request.amount * request.redemptionRateAtRequestTime / 1e18;
        uint256 fee = baseAmount * request.feeAtRequestTime / 1000000;
        uint256 amountInBase = baseAmount - fee;

        // Assert that asyncWithdrawalBalance increased by the right amount
        assertApproxEqAbs(
            assetsAfter - assetsBefore, amountInBase, 3, "asyncWithdrawalBalance should increase by the correct amount"
        );
        totalAssetsInvariant(totalAssets);
    }

    function _claimWithdrawal(address asset_, address queueManager_, uint256 tokenId) internal {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        withdrawer.processAccounting();
        uint256 totalAssets = withdrawer.totalAssets();

        vm.startPrank(ADMIN);
        queueManager.finalizeRequestsUpToIndex(tokenId + 1);
        vm.stopPrank();

        // Get the request amount in base before claiming
        IWithdrawalQueueManager.WithdrawalRequest memory request =
            IWithdrawalQueueManager(queueManager_).withdrawalRequest(tokenId);
        uint256 baseAmount = request.amount * request.redemptionRateAtRequestTime / 1e18;
        uint256 fee = baseAmount * request.feeAtRequestTime / 1000000;
        uint256 amountInBase = baseAmount - fee;

        uint256 assetsBefore = withdrawer.asyncWithdrawalBalance(asset_);

        _processClaimWithdrawal(withdrawer, queueManager_, tokenId);

        totalAssetsInvariant(totalAssets);

        uint256 assetsAfter = withdrawer.asyncWithdrawalBalance(asset_);
        // asyncWithdrawalBalance should decrease by the amount of the request
        assertApproxEqAbs(
            assetsBefore - assetsAfter, amountInBase, 3, "asyncWithdrawalBalance should decrease by the correct amount"
        );
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

    function _processRequestWithdrawal(IVault vault_, address contractAddress, address asset_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        address[] memory targets = new address[](2);
        targets[0] = asset_;
        targets[1] = contractAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", contractAddress, amount);
        data[1] = abi.encodeWithSignature("requestWithdrawal(uint256)", amount);

        bytes[] memory returnData = vault_.processor(targets, values, data);

        tokenId = abi.decode(returnData[1], (uint256));
    }

    function _processClaimWithdrawal(IVault vault_, address contractAddress, uint256 tokenId) internal {
        address[] memory targets = new address[](1);
        targets[0] = contractAddress;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("claimWithdrawal(uint256,address)", tokenId, address(vault_));

        vault_.processor(targets, values, data);
    }
}
