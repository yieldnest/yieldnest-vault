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
import {IProvider} from "src/interface/IProvider.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

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

    function setUp() public {
        SetupWithdrawer setup = new SetupWithdrawer();
        vault = setup.setup();

        // setup some default balances
        deal(MC.WETH, address(vault), INITIAL_BALANCE);
        deal(MC.YNETH, address(vault), INITIAL_BALANCE);
        deal(MC.YNLSDE, address(vault), INITIAL_BALANCE);

        deal(MC.YNETH_RAV, INITIAL_BALANCE * 100);

        address[] memory assets = IRAV(MC.YNLSDE_RAV).assetRegistry().getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            deal(assets[i], address(this), INITIAL_BALANCE * 100);
            IERC20(assets[i]).approve(MC.YNLSDE_RAV, INITIAL_BALANCE * 100);
            IRAV(MC.YNLSDE_RAV).deposit(INITIAL_BALANCE * 100, assets[i]);
        }

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

        vm.startPrank(ADMIN);
        _grantFinalizerRole(MC.YNETH_WQM, ADMIN);
        _grantFinalizerRole(MC.YNLSDE_WQM, ADMIN);
    }

    function _grantFinalizerRole(address queueManager_, address finalizer_) internal {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        bytes32 finalizerRole = queueManager.REQUEST_FINALIZER_ROLE();

        vm.startPrank(ADMIN);
        AccessControl(queueManager_).grantRole(finalizerRole, finalizer_);
        vm.stopPrank();
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

        vm.startPrank(address(vault));
        asset.approve(address(queueManager), amount);
        tokenId = queueManager.requestWithdrawal(amount);
        vm.stopPrank();

        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        assertEq(request.amount, amount, "Amount should match");

        (assets,) = vault.asyncWithdrawBalance(asset_);

        assertApproxEqRel(assets, amount, 1e14, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e14, "Total assets should match");
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

        vm.startPrank(address(vault));
        queueManager.claimWithdrawal(tokenId, address(vault));
        vm.stopPrank();

        IWithdrawalQueueManager.WithdrawalRequest memory request = queueManager.withdrawalRequest(tokenId);

        uint256 withdrawalFee = queueManager.withdrawalFee();
        uint256 amountInBase = _convertAssetToBase(asset_, request.amount);

        uint256 expectedFee = queueManager.calculateFee(amountInBase, withdrawalFee);

        assertApproxEqRel(vault.totalAssets(), totalAssets - expectedFee, 1e14, "Total assets should match");
    }

    function test_Vault_ClaimWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawal(MC.YNETH, MC.YNETH_WQM, amount);

        (uint256 assets,) = vault.asyncWithdrawBalance(MC.YNETH);
        assertApproxEqRel(assets, amount, 1e14, "Queued assets should match");

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
        assertApproxEqRel(assets, amount, 1e14, "Queued assets should match");

        uint256 rateFromProvider = provider.getRate(MC.YNLSDE);
        uint256 redemptionRate = IRAV(MC.YNLSDE_RAV).redemptionRate();

        assertEq(rateFromProvider, redemptionRate, "Rate from provider should match");

        _claimWithdrawal(MC.YNLSDE, MC.YNLSDE_WQM, tokenId);

        (assets,) = vault.asyncWithdrawBalance(MC.YNLSDE);
        assertEq(assets, 0, "Queued assets should match");
    }
}
