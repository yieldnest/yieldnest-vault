# Security Test Suite

This directory contains comprehensive security tests for vulnerabilities identified in the code review.

## Test Files

### 1. `inflationAttack.t.sol`
**Tests for CRITICAL #1: Inflation Attack Vulnerability**

Tests scenarios where attackers can dilute later depositors through:
- Basic inflation attack with small first deposit + donation
- Fuzz testing with varying donation amounts
- Demonstrating that +1 protection is insufficient
- Multiple victim scenarios
- Zero shares minted edge case
- Recommended mitigations (virtual shares, dead shares)

**Key Tests:**
- `test_InflationAttack_BasicScenario()` - Core attack demonstration
- `testFuzz_InflationAttack_VaryingDonations()` - Fuzz test with different amounts
- `test_InflationAttack_ZeroSharesMinted()` - Complete loss scenario
- `test_VirtualSharesOffset_ProperProtection()` - Recommended fix

### 2. `oracleManipulation.t.sol`
**Tests for HIGH #2: Oracle Manipulation Risks**

Tests lack of oracle validation and manipulation vectors:
- No rate bounds checking (can be 0 or max uint256)
- No staleness checks on rate updates
- No circuit breakers for large rate changes
- Rate overflow scenarios
- Flash loan manipulation
- Cross-asset rate inconsistencies
- Performance fee manipulation via rate changes

**Key Tests:**
- `test_OracleManipulation_NoRateBounds()` - Demonstrates lack of validation
- `test_OracleManipulation_NoStalenessCheck()` - Missing timestamp checks
- `test_OracleManipulation_FlashLoanAttack()` - Flash loan vulnerability
- `test_Recommendation_RateBounds()` - Recommended bounds check
- `test_Recommendation_CircuitBreaker()` - Recommended rate change limits

### 3. `nativeEthAccounting.t.sol`
**Tests for Code Review #7: Native ETH Accounting Issue**

Tests the problematic `countNativeAsset` feature:
- ETH donations increase totalAssets without minting shares
- Unfair share price inflation for existing holders
- Attacker exploitation scenarios
- Griefing attacks
- Recommended fixes (proper ETH deposit flow or disable feature)

**Key Tests:**
- `test_NativeEth_DonationInflatesSharePrice()` - Core accounting issue
- `test_NativeEth_AttackerExploitation()` - Exploitation scenario
- `test_NativeEth_ReceiveFunctionDoesntMintShares()` - receive() bug
- `test_Recommendation_DisableCountNativeAsset()` - Recommended fix

### 4. `accountingEdgeCases.t.sol`
**Tests for HIGH #4 and Various Accounting Edge Cases**

Tests accounting vulnerabilities and edge cases:
- Unchecked totalAssets underflow in `subTotalAssets`
- Rounding error accumulation
- Zero shares minted scenarios
- Dust amount handling
- totalAssets vs actual balance divergence
- Multi-user accounting invariants
- Gas cost analysis for processAccounting

**Key Tests:**
- `test_Accounting_UnderflowRisk()` - Unchecked subtraction
- `test_Accounting_ZeroSharesMinted()` - Zero shares edge case
- `test_Accounting_MultiUserInvariant()` - Invariant testing
- `test_Accounting_TotalAssetsDivergence()` - Balance divergence
- `test_Accounting_ProcessAccountingGasCost()` - Gas analysis

### 5. `feeEdgeCases.t.sol`
**Tests for MEDIUM #1: Fee Calculation Rounding Issues**

Tests withdrawal fee edge cases:
- Fee rounding causing users to need more shares than they have
- Asymmetry between previewWithdraw and previewRedeem
- Fee on very small amounts (rounds to zero)
- Fee on maximum values (no overflow)
- Fee override functionality
- Fee accumulation destination (accrues to remaining holders)
- Fee changes between preview and execution

**Key Tests:**
- `test_Fee_PreviewWithdrawRounding()` - Core rounding issue
- `test_Fee_AsymmetricPreviewFunctions()` - Preview asymmetry
- `test_Fee_MaximumBounds()` - Fee bounds checking
- `test_Fee_Destination()` - Where fees go
- `testFuzz_Fee_Calculations()` - Fuzz test fee math

## Running Tests

Run all security tests:
```bash
forge test --match-path "test/unit/vault/security/*.sol"
```

Run specific test file:
```bash
forge test --match-path "test/unit/vault/security/inflationAttack.t.sol" -vv
```

Run specific test:
```bash
forge test --match-test "test_InflationAttack_BasicScenario" -vvv
```

## Critical Findings Summary

These tests demonstrate the following CRITICAL and HIGH severity vulnerabilities:

1. **CRITICAL: Inflation Attack** - First depositor can inflate share price to steal from later depositors
2. **HIGH: Oracle Manipulation** - No validation on rates, no staleness checks, no circuit breakers
3. **HIGH: Native ETH Accounting** - ETH donations inflate share price unfairly
4. **HIGH: Accounting Underflow** - Unchecked subtraction in `subTotalAssets`
5. **MEDIUM: Fee Rounding** - Users may not be able to withdraw their max redeemable amount

## Recommended Fixes

See individual test files for detailed recommendations, but key fixes include:

1. **Inflation Attack**: Implement virtual shares offset (1e6) or mint dead shares
2. **Oracle**: Add rate bounds, staleness checks, and circuit breakers
3. **Native ETH**: Either disable `countNativeAsset` or implement proper ETH deposit with share minting
4. **Underflow**: Add explicit check before subtraction in `subTotalAssets`
5. **Fees**: Adjust preview functions to always return achievable values

## Test Coverage

These tests add coverage for:
- Edge cases with extreme values (0, 1 wei, max uint256)
- Rounding edge cases
- Multi-user interaction scenarios
- Timing attack vectors (fee changes, rate changes)
- Gas cost analysis
- Invariant properties

## Notes

- Some tests demonstrate vulnerabilities that cannot be fully exploited in test environment without modifying core contracts
- Tests marked with "Recommendation" show what proper implementations should look like
- Fuzz tests use bounded inputs to avoid unrealistic scenarios while still testing edge cases
