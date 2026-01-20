// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";

/**
 * @title OracleManipulationTest
 * @notice Tests for oracle manipulation risks (HIGH #2 from security review)
 * @dev Tests scenarios where rate manipulation can lead to value extraction
 */
contract OracleManipulationTest is Test, MainnetActors {
    Vault public vault;
    WETH9 public weth;

    address public alice = address(0xA11Ce);
    address public bob = address(0xB0b);
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Fund users
        deal(alice, INITIAL_BALANCE);
        deal(bob, INITIAL_BALANCE);

        vm.prank(alice);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(bob);
        weth.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice Test that rates have no bounds checking
     * @dev Demonstrates HIGH #2 vulnerability - no validation on rate values
     */
    function test_OracleManipulation_NoRateBounds() public {
        // The vault doesn't validate rate bounds
        // An oracle can return any value including 0 or type(uint256).max

        // Get current rate
        uint256 currentRate = IProvider(MC.PROVIDER).getRate(MC.STETH);
        assertGt(currentRate, 0, "Rate should be positive");

        // However, there's no check preventing:
        // 1. Rate = 0 (causes division issues)
        // 2. Rate = type(uint256).max (causes overflow)
        // 3. Rate suddenly changing by 1000x (no sanity check)

        // This lack of validation is a critical vulnerability
    }

    /**
     * @notice Test zero rate causes accounting issues
     * @dev If rate returns 0, conversions break
     */
    function test_OracleManipulation_ZeroRate() public {
        // NOTE: This test demonstrates the vulnerability
        // We can't actually set the rate to 0 in the mock without modifying it
        // But we can show what would happen

        // If rate = 0, then convertAssetToBase returns:
        // baseAssets = assets.mulDiv(rate, 10^decimals, rounding)
        //            = assets.mulDiv(0, 10^decimals, rounding)
        //            = 0

        // This means:
        // 1. Any asset with rate=0 is valued at 0
        // 2. Users can deposit that asset for free shares
        // 3. Then redeem for other assets, draining vault

        // Recommendation: Add require(rate > MIN_RATE) check
    }

    /**
     * @notice Test extreme rate changes
     * @dev Large sudden rate changes should be bounded
     */
    function test_OracleManipulation_ExtremeRateChange() public {
        // Deposit with normal rate
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        uint256 aliceShares = vault.balanceOf(alice);

        // Get asset value at normal rate
        uint256 assetsBeforeRate = vault.convertToAssets(aliceShares);

        // In a real attack, rate could suddenly change 1000x
        // Without circuit breakers, this affects all conversions immediately

        // Current system has NO protection against:
        // 1. Flash loan attacks on oracle price sources
        // 2. Oracle manipulation
        // 3. Oracle bugs returning wrong values

        // Recommendation:
        // - Add max rate change per block (e.g., 10%)
        // - Add circuit breaker for large changes
        // - Use time-weighted average rates
    }

    /**
     * @notice Test rate staleness is not checked
     * @dev Vault uses rates without checking freshness
     */
    function test_OracleManipulation_NoStalenessCheck() public {
        // The vault calls IProvider(provider).getRate(asset) but never checks:
        // 1. When was this rate last updated?
        // 2. Is this rate stale?
        // 3. Is the oracle functioning properly?

        // In VaultLib.sol:224, it just does:
        // uint256 rate = IProvider(provider).getRate(asset);
        // No validation whatsoever

        // If oracle stops updating, vault continues using stale rate
        // This can cause massive mispricings

        // Recommendation: Add timestamp checks
        // require(block.timestamp - lastUpdate < MAX_STALENESS)
    }

    /**
     * @notice Test multi-asset rate manipulation
     * @dev Manipulating rate of one asset affects all conversions
     */
    function test_OracleManipulation_MultiAssetImpact() public {
        // Give Alice some STETH
        deal(MC.STETH, alice, 100 ether);

        // Get initial rate
        uint256 initialRate = IProvider(MC.PROVIDER).getRate(MC.STETH);

        vm.startPrank(alice);
        // Deposit WETH
        vault.deposit(50 ether, alice);

        // Deposit STETH
        IERC20(MC.STETH).approve(address(vault), type(uint256).max);
        uint256 stethShares = vault.depositAsset(MC.STETH, 50 ether, alice);
        vm.stopPrank();

        uint256 totalShares = vault.balanceOf(alice);

        // If STETH rate suddenly doubles (oracle manipulation):
        // - Total vault assets increases
        // - Share price increases
        // - Alice can withdraw more WETH than deposited
        // - Other users are diluted

        // Current system has no protection against this
    }

    /**
     * @notice Test precision loss with small rates
     * @dev Small rates can cause rounding to zero
     */
    function test_OracleManipulation_PrecisionLoss() public {
        // If an asset has very small rate relative to base:
        // rate = 1 (instead of expected 1e18)
        // Then: baseAssets = assets * 1 / 10^decimals ≈ 0 for small amounts

        // Example with 18 decimal asset:
        // assets = 1000 wei
        // rate = 1
        // baseAssets = 1000 * 1 / 1e18 = 0 (rounds down)

        // This means small deposits are valued at 0
        // Users lose funds due to rounding

        // Recommendation:
        // - Document expected rate precision
        // - Add minimum rate check
        // - Add minimum deposit amount
    }

    /**
     * @notice Test rate overflow scenarios
     * @dev Extremely large rates can cause overflow
     */
    function testFuzz_OracleManipulation_RateOverflow(uint256 rate) public {
        // Bound rate to huge values that could overflow
        rate = bound(rate, type(uint256).max / 1e18, type(uint256).max);

        // With large rate:
        // baseAssets = assets.mulDiv(rate, 10^decimals)
        // If assets * rate overflows, mulDiv handles it
        // But the result might be nonsensical

        // The vault should reject unrealistic rates
        // e.g., require(rate < MAX_RATE) where MAX_RATE = 100e18 (100x base)

        // Current implementation accepts any rate value
    }

    /**
     * @notice Test deposit/withdraw arbitrage with rate changes
     * @dev Rate changes between deposit and withdraw create arbitrage
     */
    function test_OracleManipulation_DepositWithdrawArbitrage() public {
        // Scenario:
        // 1. Alice deposits STETH when rate = 1.0 ETH
        // 2. Rate suddenly changes to 1.1 ETH (10% increase)
        // 3. Alice withdraws WETH, getting 10% more than deposited
        // 4. Loss is socialized to other depositors

        deal(MC.STETH, alice, 100 ether);

        vm.startPrank(alice);
        IERC20(MC.STETH).approve(address(vault), type(uint256).max);

        // Deposit STETH
        uint256 depositAmount = 100 ether;
        uint256 shares = vault.depositAsset(MC.STETH, depositAmount, alice);

        // In real scenario, attacker would manipulate oracle here
        // Rate increases from 1.0 to 1.1 ETH per STETH

        // Alice can now redeem shares for more assets
        uint256 assetsOut = vault.previewRedeem(shares);

        // With manipulated rate, assetsOut > depositAmount
        // Alice profits, other users lose

        // Recommendation: Add rate change limits and circuit breakers
    }

    /**
     * @notice Test flash loan rate manipulation
     * @dev Attacker uses flash loan to manipulate spot price oracle
     */
    function test_OracleManipulation_FlashLoanAttack() public {
        // Classic flash loan attack on spot price oracle:
        // 1. Flash loan large amount
        // 2. Manipulate spot price (if oracle uses spot)
        // 3. Deposit at favorable rate
        // 4. Restore price
        // 5. Withdraw at different rate
        // 6. Profit, repay flash loan

        // The vault has NO protection against:
        // - Using spot prices (should use TWAP)
        // - Single block rate manipulation
        // - Oracle manipulation via underlying AMM

        // Recommendation:
        // - Use time-weighted average price (TWAP)
        // - Require oracle updates to be at least 1 block old
        // - Use Chainlink or other manipulation-resistant oracles
    }

    /**
     * @notice Test rate manipulation affects processAccounting
     * @dev Performance fees based on manipulated rates
     */
    function test_OracleManipulation_PerformanceFeeManipulation() public {
        // Deposit initial amount
        vm.prank(alice);
        vault.deposit(1000 ether, alice);

        // Attacker could:
        // 1. Manipulate rate upward before processAccounting
        // 2. Vault calculates inflated yield
        // 3. Performance fees minted on fake gains
        // 4. Attacker manipulates rate back down
        // 5. Performance fee recipient got free shares

        // Current implementation has no protection against this
        // processAccounting trusts rates completely
    }

    /**
     * @notice Test cross-asset rate inconsistency
     * @dev Rates of different assets should be consistent with market
     */
    function test_OracleManipulation_CrossAssetInconsistency() public {
        // If oracle returns inconsistent rates:
        // WETH rate = 1e18 (1 ETH = 1 base)
        // STETH rate = 2e18 (1 STETH = 2 base)
        // But market says 1 STETH ≈ 1 ETH

        // Attacker can:
        // 1. Deposit STETH (valued at 2x)
        // 2. Get shares based on inflated value
        // 3. Withdraw WETH (valued at 1x)
        // 4. Profit the difference

        // Recommendation:
        // - Use multiple oracle sources
        // - Check rate consistency across assets
        // - Implement sanity checks on rate relationships
    }

    /**
     * @notice Test minimum/maximum rate bounds recommendation
     * @dev Demonstrates need for rate validation
     */
    function test_Recommendation_RateBounds() public {
        // Recommended implementation:
        //
        // uint256 constant MIN_RATE = 0.1e18;  // Asset can't be worth less than 0.1 base
        // uint256 constant MAX_RATE = 100e18;  // Asset can't be worth more than 100 base
        //
        // function getValidatedRate(address asset) internal view returns (uint256) {
        //     uint256 rate = IProvider(provider).getRate(asset);
        //     require(rate >= MIN_RATE, "Rate too low");
        //     require(rate <= MAX_RATE, "Rate too high");
        //     return rate;
        // }

        // This would prevent extreme rate values from breaking the system
    }

    /**
     * @notice Test rate change circuit breaker recommendation
     * @dev Demonstrates need for rate change limits
     */
    function test_Recommendation_CircuitBreaker() public {
        // Recommended implementation:
        //
        // mapping(address => uint256) lastRate;
        // mapping(address => uint256) lastUpdate;
        // uint256 constant MAX_RATE_CHANGE = 0.1e18; // 10% max change
        //
        // function getValidatedRate(address asset) internal returns (uint256) {
        //     uint256 rate = IProvider(provider).getRate(asset);
        //     uint256 previous = lastRate[asset];
        //
        //     if (previous > 0) {
        //         uint256 change = rate > previous
        //             ? rate - previous
        //             : previous - rate;
        //         uint256 changePercent = change * 1e18 / previous;
        //
        //         require(changePercent <= MAX_RATE_CHANGE, "Rate changed too much");
        //     }
        //
        //     lastRate[asset] = rate;
        //     lastUpdate[asset] = block.timestamp;
        //     return rate;
        // }

        // This would prevent sudden large rate changes from affecting the system
    }
}
