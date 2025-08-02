// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Math} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {MockStakeHub} from "test/mainnet/mocks/MockStakeHub.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract WithdrawerMainnetTest is Test, AssertUtils, MainnetActors {
    using Math for uint256;

    Withdrawer public vault;
    uint256 public constant INITIAL_BALANCE = 100 ether;

    address public constant SLIS_ADMIN = 0x5C0F11c927216E4D780E2a219b06632Fb027274E;

    IProvider public provider;

    function setUp() public {
        SetupWithdrawer setup = new SetupWithdrawer();
        vault = setup.setup();

        // NOTE: setup some default balances for the vault
        deal(MC.WBNB, address(vault), INITIAL_BALANCE);
        deal(MC.SLISBNB, address(vault), INITIAL_BALANCE);

        // NOTE: donate some assets to the queue managers / redemption assets vaults
        deal(MC.SLIS_BNB_STAKE_MANAGER, INITIAL_BALANCE * 100);

        vm.startPrank(ADMIN);
        vault.grantRole(vault.PROCESSOR_ROLE(), address(this));
        vm.stopPrank();

        provider = IProvider(vault.provider());

        _mockSlisValidator();
    }

    function _mockSlisValidator() internal {
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);
        bytes32 botRole = stakeManager.BOT();

        vm.startPrank(SLIS_ADMIN);
        AccessControl(MC.SLIS_BNB_STAKE_MANAGER).grantRole(botRole, address(this));
        stakeManager.whitelistValidator(address(this));
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

    function test_Vault_views() public {
        assertEq(vault.countNativeAsset(), true, "Native asset should be counted");
        assertEq(vault.alwaysComputeTotalAssets(), false, "Always compute total assets should be true");
        assertEq(vault.asset(), MC.WETH, "Asset address should match");

        uint256 totalAssets = INITIAL_BALANCE; // WBNB
        totalAssets += _convertAssetToBase(MC.SLISBNB, INITIAL_BALANCE); // SLISBNB
        vault.processAccounting();
        assertEq(vault.totalAssets(), totalAssets, "Total assets should match");
    }

    function test_Vault_RequestWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1 ether);
        vm.assume(amount < INITIAL_BALANCE / 2);

        _requestWithdrawal(amount);
    }

    function test_Vault_ClaimWithdrawal_YNETH(uint256 amount) public {
        vm.assume(amount > 1 ether);
        vm.assume(amount < INITIAL_BALANCE / 2);

        uint256 tokenId = _requestWithdrawal(amount);

        _claimWithdrawal(tokenId);
    }

    function _requestWithdrawal(uint256 amount) internal returns (uint256 tokenId) {
        address asset_ = MC.SLISBNB;
        address stakeManager_ = MC.SLIS_BNB_STAKE_MANAGER;
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(stakeManager_);

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should be zero");
        vault.processAccounting();
        uint256 totalAssets = vault.totalAssets();

        _processRequestWithdraw(vault, stakeManager_, asset_, amount);

        ISlisBnbStakeManager.WithdrawalRequest[] memory requests =
            stakeManager.getUserWithdrawalRequests(address(vault));
        tokenId = requests.length - 1;

        (bool _isClaimable, uint256 _amount) = stakeManager.getUserRequestStatus(address(vault), tokenId);
        uint256 amountInBase = _convertAssetToBase(asset_, amount);

        assertEq(_isClaimable, false, "Claimable should be false");
        assertApproxEqRel(_amount, amountInBase, 1e15, "Amount should match");

        assets = vault.asyncWithdrawalBalance(asset_);

        assertApproxEqRel(assets, amountInBase, 1e15, "Queued assets should match");
        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");

        vault.processAccounting();
    }

    function _claimWithdrawal(uint256 tokenId) internal {
        address asset_ = MC.SLISBNB;
        address stakeManager_ = MC.SLIS_BNB_STAKE_MANAGER;
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(stakeManager_);
        MockStakeHub stakeHub = MockStakeHub(MC.SLIS_BNB_STAKE_HUB);

        uint256 totalAssets = vault.totalAssets();

        stakeManager.undelegateFrom(address(this), stakeManager.getAmountToUndelegate() + stakeManager.reserveAmount());
        uint256 claimAmount = stakeManager.unbondingBnb();
        deal(address(this), claimAmount);
        stakeHub.stake{value: claimAmount}();
        stakeManager.claimUndelegated(address(this));

        (bool _isClaimable,) = stakeManager.getUserRequestStatus(address(vault), tokenId);
        assertEq(_isClaimable, true, "Claimable should be true");

        _processClaimWithdraw(vault, stakeManager_, tokenId);

        assertApproxEqRel(vault.totalAssets(), totalAssets, 1e15, "Total assets should match");

        uint256 assets = vault.asyncWithdrawalBalance(asset_);
        assertEq(assets, 0, "Queued assets should match");
    }

    function _processRequestWithdraw(Withdrawer vault_, address contractAddress, address asset_, uint256 amount)
        internal
    {
        address[] memory targets = new address[](2);
        targets[0] = asset_;
        targets[1] = contractAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", contractAddress, amount);
        data[1] = abi.encodeWithSignature("requestWithdraw(uint256)", amount);

        vault_.processor(targets, values, data);
    }

    function _processClaimWithdraw(Withdrawer vault_, address contractAddress, uint256 tokenId) internal {
        address[] memory targets = new address[](1);
        targets[0] = contractAddress;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("claimWithdraw(uint256)", tokenId);

        vault_.processor(targets, values, data);
    }
}
