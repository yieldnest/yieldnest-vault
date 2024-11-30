// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IValidator} from "src/interface/IValidator.sol";

// Mock validator contract for testing
contract MockValidator is IValidator {
    bool public validationResult = true;

    function setValidationResult(bool result) external {
        validationResult = result;
    }

    function validate(address target, uint256 value, bytes calldata data) external view {
        require(validationResult, "Validation failed");
    }
}

contract VaultProcessUnitTest is Test, MainnetActors, Etches {
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

    function test_Vault_processAccounting_idleAssets() public {
        // Simulate some asset and strategy balances
        deal(alice, 200 ether); // Simulate some ether balance for the vault
        weth.deposit{value: 100 ether}(); // Deposit ether into WETH
        steth.deposit{value: 100 ether}(); // Mint some STETH

        // Set up some initial balances for assets and strategies
        vm.prank(alice);
        weth.transfer(address(vault), 50 ether); // Transfer some WETH to the vault
        steth.transfer(address(vault), 50 ether); // Transfer some STETH to the vault

        vault.processAccounting();
    }

    function test_Vault_processor_fails_with_invalid_asset_approve() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(420);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(vault), 50 ether);

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_with_invalid_asset_transfer() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(weth);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", address(vault), 50 ether);

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_ValueAboveMaximum() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(MC.YNETH);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 100_001 ether, address(vault));

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_ValueBelowMinimum() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = MC.YNETH;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 1, address(vault));

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_AddressNotInAllowlist() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = MC.YNETH;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 100, address(420));

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_getProcessorRule() public view {
        bytes4 sig = bytes4(keccak256("deposit(uint256,address)"));
        IVault.FunctionRule memory rule = vault.getProcessorRule(MC.BUFFER, sig);
        IVault.FunctionRule memory expectedResult;
        expectedResult.isActive = true;
        expectedResult.paramRules = new IVault.ParamRule[](2);
        expectedResult.paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        expectedResult.paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: new address[](1)});
        expectedResult.paramRules[1].allowList[0] = address(vault);

        // Add assertions
        assertEq(rule.isActive, expectedResult.isActive, "isActive does not match");
        assertEq(rule.paramRules.length, expectedResult.paramRules.length, "paramRules length does not match");

        for (uint256 i = 0; i < rule.paramRules.length; i++) {
            assertEq(
                uint256(rule.paramRules[i].paramType),
                uint256(expectedResult.paramRules[i].paramType),
                "paramType does not match"
            );
            assertEq(rule.paramRules[i].isArray, expectedResult.paramRules[i].isArray, "isArray does not match");
            assertEq(
                rule.paramRules[i].allowList.length,
                expectedResult.paramRules[i].allowList.length,
                "allowList length does not match"
            );

            for (uint256 j = 0; j < rule.paramRules[i].allowList.length; j++) {
                assertEq(
                    rule.paramRules[i].allowList[j],
                    expectedResult.paramRules[i].allowList[j],
                    "allowList element does not match"
                );
            }
        }
    }

    function test_Vault_processorCall_failsWithBadTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0); // Invalid target address

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 100, address(420));

        // Expect the processor call to fail with an invalid target
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processorCall_failsWithBadCalldata() public {
        // make sure the processor rule has been set

        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vm.prank(PROCESSOR_MANAGER);
        vault.setProcessorRule(MC.BUFFER, funcSig, rule);

        address[] memory targets = new address[](1);
        targets[0] = MC.BUFFER;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 10000000 ether, address(vault)); // Invalid function signature

        // Expect the processor call to fail with and send return data
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function _setupValidatorRule() internal returns (MockValidator) {
        bytes4 funcSig = bytes4(keccak256("deposit2()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        // First param rule for uint256 amount
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Second param rule for address receiver
        address[] memory allowList = new address[](1);
        // set to wrong target, but should be ignored
        allowList[0] = address(MC.YNETH);
        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        // Create mock validator contract
        MockValidator validator = new MockValidator();

        // Create rule with validator
        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(validator))});

        // Set the rule
        vm.prank(PROCESSOR_MANAGER);
        vault.setProcessorRule(MC.STETH, funcSig, rule);

        // Verify rule was set correctly
        IVault.FunctionRule memory setRule = vault.getProcessorRule(MC.STETH, funcSig);
        assertTrue(setRule.isActive, "Rule should be active");
        assertEq(address(setRule.validator), address(validator), "Validator address should match");
        assertEq(setRule.paramRules.length, paramRules.length, "Param rules length should match");

        return validator;
    }

    function test_Vault_processorRule_withValidator_success() public {
        MockValidator validator = _setupValidatorRule();

        // Send 10 ether to vault
        deal(address(vault), 10 ether);

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = MC.STETH;

        uint256[] memory values = new uint256[](1);
        values[0] = 10 ether;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit2()");

        validator.setValidationResult(true);

        // Call processor with 10 ether value
        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function test_Vault_processorRule_withValidator_failure() public {
        MockValidator validator = _setupValidatorRule();

        // Send 10 ether to vault
        deal(address(vault), 10 ether);

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = MC.STETH;

        uint256[] memory values = new uint256[](1);
        values[0] = 10 ether;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit2()");

        validator.setValidationResult(false);

        // Call processor with 10 ether value
        vm.prank(PROCESSOR);
        vm.expectRevert("Validation failed");
        vault.processor(targets, values, data);
    }
}
