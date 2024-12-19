// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";

contract VaultDepositUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MC.STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_deposit_success(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        // uint256 depositAmount = 100 * 10 ** 18;
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that the vault received the tokens
        assertEq(weth.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    event Log(string, uint256);

    function test_Vault_depositAsset_STETH(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(address(steth), alice, depositAmount);

        vm.startPrank(alice);

        uint256 previewDepositAsset = vault.previewDepositAsset(address(steth), depositAmount);

        steth.approve(address(vault), depositAmount);

        uint256 sharesMinted = vault.depositAsset(address(steth), depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");
        assertEq(sharesMinted, previewDepositAsset, "Incorrect shares minted");

        // Check that the vault received the tokens
        assertEq(steth.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(steth.balanceOf(alice), 0, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), previewDepositAsset, "Total assets did not increase correctly");

        vm.stopPrank();
    }

    function test_Vault_depositAsset_METH(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.METH, alice, depositAmount);

        vm.startPrank(alice);

        uint256 previewDepositAsset = vault.previewDepositAsset(MC.METH, depositAmount);

        IERC20(MC.METH).approve(address(vault), depositAmount);

        uint256 sharesMinted = vault.depositAsset(MC.METH, depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");
        assertEq(sharesMinted, previewDepositAsset, "Incorrect shares minted");

        // Check that the vault received the tokens
        assertEq(IERC20(MC.METH).balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(IERC20(MC.METH).balanceOf(alice), 0, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), previewDepositAsset, "Total assets did not increase correctly");

        // Check that rate is correct
        uint256 methRate = IProvider(MC.PROVIDER).getRate(MC.METH);

        // Check that total assets matches rate-adjusted deposit
        uint256 expectedTotalAssets = depositAmount * methRate / 1e18;
        assertEq(vault.totalAssets(), expectedTotalAssets, "Total assets does not match rate-adjusted deposit");

        vm.stopPrank();
    }

    function test_Vault_depositAsset_WBTC(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 * 1e8) return; // WBTC has 8 decimals

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.WBTC, alice, depositAmount);

        vm.startPrank(alice);

        uint256 previewDepositAsset = vault.previewDepositAsset(MC.WBTC, depositAmount);

        IERC20(MC.WBTC).approve(address(vault), depositAmount);

        uint256 sharesMinted = vault.depositAsset(MC.WBTC, depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");
        assertEq(sharesMinted, previewDepositAsset, "Incorrect shares minted");

        // Check that the vault received the tokens
        assertEq(IERC20(MC.WBTC).balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(IERC20(MC.WBTC).balanceOf(alice), 0, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), previewDepositAsset, "Total assets did not increase correctly");

        // Check that rate is correct
        uint256 wbtcRate = IProvider(MC.PROVIDER).getRate(MC.WBTC);

        // Check that total assets matches rate-adjusted deposit
        // Need to account for WBTC's 8 decimals vs ETH's 18 decimals
        uint256 expectedTotalAssets = depositAmount * wbtcRate / 1e8;
        assertEq(vault.totalAssets(), expectedTotalAssets, "Total assets does not match rate-adjusted deposit");

        vm.stopPrank();
    }

    function test_Vault_multiAssetDeposit_processAccounting(
        uint256 wethAmount,
        uint256 wbtcAmount,
        uint256 methAmount,
        bool alwaysComputeTotalAssets
    ) public {
        // Bound inputs to reasonable ranges
        wethAmount = bound(wethAmount, 1 ether, 10_000 ether);
        wbtcAmount = bound(wbtcAmount, 1e6, 1000e8); // 0.01 to 100 WBTC
        methAmount = bound(methAmount, 1 ether, 10_000 ether);

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Get initial rates
        uint256 wbtcRate = IProvider(MC.PROVIDER).getRate(MC.WBTC);
        uint256 methRate = IProvider(MC.PROVIDER).getRate(MC.METH);

        // Deal tokens to alice
        deal(MC.WBTC, alice, wbtcAmount);
        deal(MC.METH, alice, methAmount);

        vm.startPrank(alice);

        // First deposit WETH
        uint256 wethShares = vault.deposit(wethAmount, alice);
        assertEq(IERC20(MC.WETH).balanceOf(address(vault)), wethAmount, "Vault WETH balance incorrect");
        assertEq(vault.balanceOf(alice), wethShares, "Alice WETH shares incorrect");

        // Then deposit WBTC
        IERC20(MC.WBTC).approve(address(vault), wbtcAmount);
        uint256 wbtcShares = vault.depositAsset(MC.WBTC, wbtcAmount, alice);
        assertEq(IERC20(MC.WBTC).balanceOf(address(vault)), wbtcAmount, "Vault WBTC balance incorrect");
        assertEq(vault.balanceOf(alice), wethShares + wbtcShares, "Alice total shares incorrect after WBTC");

        // Finally deposit METH
        IERC20(MC.METH).approve(address(vault), methAmount);
        uint256 methShares = vault.depositAsset(MC.METH, methAmount, alice);
        assertEq(IERC20(MC.METH).balanceOf(address(vault)), methAmount, "Vault METH balance incorrect");
        assertEq(
            vault.balanceOf(alice), wethShares + wbtcShares + methShares, "Alice total shares incorrect after METH"
        );

        vm.stopPrank();

        // Calculate expected total assets in base units (ETH)
        uint256 expectedTotal = wethAmount // WETH is already in ETH units
            + (wbtcAmount * wbtcRate) / 1e8 // Convert WBTC to ETH units
            + (methAmount * methRate) / 1e18; // Convert METH to ETH units

        // Assert total assets before processAccounting
        assertEq(vault.totalAssets(), expectedTotal, "Total assets incorrect before processAccounting");

        // Process accounting and verify total stays the same
        vault.processAccounting();
        assertEq(vault.totalAssets(), expectedTotal, "Total assets changed after processAccounting");
    }

    function test_Vault_mint(uint256 mintAmount, bool alwaysComputeTotalAssets) public {
        if (mintAmount < 10) return;
        if (mintAmount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        vm.startPrank(alice);
        uint256 sharesMinted = vault.mint(mintAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets did not change
        assertEq(vault.totalAssets(), mintAmount, "Total assets changed incorrectly");

        vm.stopPrank();
    }

    function test_Vault_depositAsset_WrongAsset() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.depositAsset(address(0), 100, alice);
    }

    function test_Vault_depositAssetWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.depositAsset(address(0), 1000, alice);
    }

    function test_Vault_mintWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.mint(1000, alice);
    }

    function test_Vault_pauseAndDeposit() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1000, alice);
    }

    function test_Vault_maxMint() public view {
        uint256 maxMint = vault.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "Max mint does not match");
    }

    function test_Vault_previewDeposit(uint256 assets, bool alwaysComputeTotalAssets) public {
        if (assets < 10) return;
        if (assets > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, assets, "Preview deposit does not match expected shares");
    }

    function test_Vault_previewMint(uint256 shares, bool alwaysComputeTotalAssets) public {
        if (shares < 10) return;
        if (shares > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 assets = vault.previewMint(shares);
        assertEq(assets, shares, "Preview mint does not match expected assets");
    }

    function test_Vault_getAsset() public view {
        address assetAddress = MC.WETH;
        IVault.AssetParams memory expectedAssetParams = IVault.AssetParams({active: true, index: 0, decimals: 18});
        assertEq(vault.getAsset(assetAddress).active, expectedAssetParams.active);
        assertEq(vault.getAsset(assetAddress).index, expectedAssetParams.index);
        assertEq(vault.getAsset(assetAddress).decimals, expectedAssetParams.decimals);
    }

    function test_Vault_maxDeposit() public view {
        uint256 maxDeposit = vault.maxDeposit(alice);
        assertEq(maxDeposit, type(uint256).max, "Max deposit does not match");
    }

    function test_Vault_previewDepositAsset() public view {
        uint256 assets = 1000;
        uint256 expectedShares = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 shares = vault.previewDepositAsset(MC.WETH, assets);
        assertEq(shares, expectedShares, "Preview deposit asset does not match expected shares");
    }

    function test_Vault_previewDepositAsset_WrongAsset() public {
        address invalidAssetAddress = address(0);
        uint256 assets = 1000;
        vm.expectRevert();
        vault.previewDepositAsset(invalidAssetAddress, assets);
    }

    function test_Vault_maxMint_whenPaused_shouldRevert() public {
        // Pause the vault
        vm.prank(ADMIN);
        vault.pause();

        // Expect revert when calling maxMint while paused
        assertEq(vault.maxMint(alice), 0, "Should be zero when paused");
    }

    function test_Vault_maxRedeem_whenPaused_shouldRevert() public {
        // Pause the vault
        vm.prank(ADMIN);
        vault.pause();

        // Expect revert when calling maxRedeem while paused
        assertEq(vault.maxRedeem(alice), 0, "Should be zero when paused");
    }

    function test_Vault_receiveETH(uint256 depositAmount) public {
        if (depositAmount < 1 || depositAmount > 100_000_00 ether) return;

        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success == true, "Deposit eth failed");
        vault.processAccounting();

        // Check the shares minted
        uint256 assets = vault.totalAssets();
        assertEq(depositAmount, assets, "No shares minted");
    }

    function test_Vault_depositAsset_InvalidAsset() public {
        // Deploy a random ERC20 token that hasn't been added to vault
        MockERC20 randomToken = new MockERC20("Random", "RND");

        vm.startPrank(alice);
        // Mint some tokens to alice
        randomToken.mint(1000);

        // Try to deposit the random token
        randomToken.approve(address(vault), 1000);
        bytes memory encodedError = abi.encodeWithSelector(Provider.UnsupportedAsset.selector, address(randomToken));
        vm.expectRevert(encodedError);
        vault.depositAsset(address(randomToken), 1000, alice);
        vm.stopPrank();
    }

    function test_Vault_depositAsset_BufferAsset() public {
        // Get the buffer asset address
        address bufferAsset = MC.BUFFER;

        // Try to deposit the buffer asset
        address user = address(0xdeadbeef);
        vm.startPrank(user);

        // Give user some ETH and convert to WETH
        deal(user, 1000);
        weth.deposit{value: 1000}();

        // Deposit WETH to buffer to get buffer tokens
        weth.approve(MC.BUFFER, 1000);
        IERC4626(MC.BUFFER).deposit(1000, user);

        IERC4626(MC.BUFFER).approve(address(vault), 1000);

        vm.expectRevert(IVault.AssetNotActive.selector);
        vault.depositAsset(bufferAsset, 1000, user);
        vm.stopPrank();
    }

    function test_maxDeposit_is_zero_when_paused() public {
        // Pause the vault
        vm.startPrank(PAUSER);
        vault.pause();

        // Check that maxDeposit is zero for Alice
        uint256 maxDepositAmount = vault.maxDeposit(alice);
        assertEq(maxDepositAmount, 0, "maxDeposit should be zero when paused");

        // Unpause the vault
        vm.startPrank(UNPAUSER);
        vault.unpause();

        // Check that maxDeposit is no longer zero for Alice
        maxDepositAmount = vault.maxDeposit(alice);
        assertGt(maxDepositAmount, 0, "maxDeposit should not be zero when unpaused");
    }

    event ReferralDepositProcessed(
        address vault,
        address asset,
        address indexed depositor,
        address indexed referrer,
        address indexed receiver,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    function testFuzz_xReferralAdapter_deposit_success(uint256 assets) public {
        vm.assume(assets > 0 && assets < type(uint128).max);
        XReferralAdapter referallAdapter = new XReferralAdapter();

        uint256 previewShares = vault.previewDeposit(assets);

        deal(address(weth), alice, assets);

        vm.prank(alice);
        weth.approve(address(referallAdapter), assets);

        vm.expectEmit(true, true, true, true);
        emit ReferralDepositProcessed(
            address(vault), address(weth), address(alice), address(this), alice, assets, previewShares, block.timestamp
        );
        vm.prank(alice);
        uint256 shares =
            referallAdapter.depositAssetWithReferral(address(vault), address(weth), assets, address(this), alice);
        assertEq(shares, previewShares, "shares should be correct");
        assertEq(vault.balanceOf(alice), shares, "alice should have the shares");
    }

    function test_xReferralAdapter_depost_revert_InvalidVault() public {
        XReferralAdapter referallAdapter = new XReferralAdapter();
        Vault emptyVault = new Vault();
        uint256 assets = 1 ether;
        vm.expectRevert();
        vm.prank(alice);
        uint256 shares =
            referallAdapter.depositAssetWithReferral(address(emptyVault), address(weth), assets, address(this), alice);
    }

    function test_xReferralAdapter_deposit_revert_ZeroAddress() public {
        XReferralAdapter referallAdapter = new XReferralAdapter();
        uint256 assets = 1 ether;

        vm.expectRevert(XReferralAdapter.ZeroAddress.selector);
        vm.prank(alice);
        referallAdapter.depositAssetWithReferral(address(vault), address(0), assets, address(this), alice);

        vm.expectRevert(XReferralAdapter.ZeroAddress.selector);
        vm.prank(alice);
        referallAdapter.depositAssetWithReferral(address(vault), address(weth), assets, address(0), alice);

        vm.expectRevert(XReferralAdapter.ZeroAddress.selector);
        vm.prank(alice);
        referallAdapter.depositAssetWithReferral(address(vault), address(weth), assets, address(this), address(0));
    }

    function test_xReferralAdapter_deposit_revert_ZeroAmount() public {
        XReferralAdapter referallAdapter = new XReferralAdapter();

        vm.expectRevert(XReferralAdapter.ZeroAmount.selector);
        vm.prank(alice);
        referallAdapter.depositAssetWithReferral(address(vault), address(weth), 0, address(this), alice);
    }

    function test_xReferralAdapter_deposit_revert_SelfReferall() public {
        XReferralAdapter referallAdapter = new XReferralAdapter();

        vm.expectRevert(XReferralAdapter.SelfReferral.selector);
        vm.prank(alice);
        referallAdapter.depositAssetWithReferral(address(vault), address(weth), 1 ether, alice, alice);
    }
}
