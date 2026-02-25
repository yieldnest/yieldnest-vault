// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {IVault} from "src/interface/IVault.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20Metadata} from "src/Common.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ViewUtils} from "test/utils/ViewUtils.sol";
import {Ownable} from "src/Common.sol";

interface IProcessAccountingGuardHook {
    function setMaxTotalAssetsDecreaseRatio(uint256 _maxTotalAssetsDecreaseRatio) external;
    function setMaxTotalAssetsIncreaseRatio(uint256 _maxTotalAssetsIncreaseRatio) external;
    function setMaxTotalSupplyIncreaseRatio(uint256 _maxTotalSupplyIncreaseRatio) external;
    function setExpectedPerformanceFee(uint256 _expectedPerformanceFee) external;

    function owner() external view returns (address);
}

library HooksUtils {
    using Math for uint256;

    Vm constant vm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));

    /**
     * @notice Set the maximum totalAssets decrease ratio on the ProcessAccountingGuardHook for the given vault
     * @param vault The vault to target
     * @param _maxTotalAssetsDecreaseRatio The maximum totalAssets decrease ratio
     */
    function setMaxTotalAssetsDecreaseRatio(IVault vault, uint256 _maxTotalAssetsDecreaseRatio) internal {
        address guardHook = ViewUtils.getHooks(vault, "ProcessAccountingGuardHook");
        address owner = IProcessAccountingGuardHook(guardHook).owner();
        vm.startPrank(owner);
        IProcessAccountingGuardHook(guardHook).setMaxTotalAssetsDecreaseRatio(_maxTotalAssetsDecreaseRatio);
        vm.stopPrank();
    }

    /**
     * @notice Set the maximum totalAssets increase ratio on the ProcessAccountingGuardHook for the given vault
     * @param vault The vault to target
     * @param _maxTotalAssetsIncreaseRatio The maximum totalAssets increase ratio
     */
    function setMaxTotalAssetsIncreaseRatio(IVault vault, uint256 _maxTotalAssetsIncreaseRatio) internal {
        address guardHook = ViewUtils.getHooks(vault, "ProcessAccountingGuardHook");
        address owner = IProcessAccountingGuardHook(guardHook).owner();
        vm.startPrank(owner);
        IProcessAccountingGuardHook(guardHook).setMaxTotalAssetsIncreaseRatio(_maxTotalAssetsIncreaseRatio);
        vm.stopPrank();
    }

    /**
     * @notice Set the maximum totalSupply increase ratio on the ProcessAccountingGuardHook for the given vault
     * @param vault The vault to target
     * @param _maxTotalSupplyIncreaseRatio The maximum totalSupply increase ratio
     */
    function setMaxTotalSupplyIncreaseRatio(IVault vault, uint256 _maxTotalSupplyIncreaseRatio) internal {
        address guardHook = ViewUtils.getHooks(vault, "ProcessAccountingGuardHook");
        address owner = IProcessAccountingGuardHook(guardHook).owner();
        vm.startPrank(owner);
        IProcessAccountingGuardHook(guardHook).setMaxTotalSupplyIncreaseRatio(_maxTotalSupplyIncreaseRatio);
        vm.stopPrank();
    }

    /**
     * @notice Set the expected performance fee on the ProcessAccountingGuardHook for the given vault
     * @param vault The vault to target
     * @param _expectedPerformanceFee The expected performance fee
     */
    function setExpectedPerformanceFee(IVault vault, uint256 _expectedPerformanceFee) internal {
        address guardHook = ViewUtils.getHooks(vault, "ProcessAccountingGuardHook");
        address owner = IProcessAccountingGuardHook(guardHook).owner();
        vm.startPrank(owner);
        IProcessAccountingGuardHook(guardHook).setExpectedPerformanceFee(_expectedPerformanceFee);
        vm.stopPrank();
    }

    /**
     * @notice Set the performance fee on the ProcessAccountingGuardHook for the given vault
     * @param vault The vault to target
     * @param _performanceFee The new performance fee
     */
    function setPerformanceFee(IVault vault, uint256 _performanceFee) internal {
        address hook = ViewUtils.getHooks(vault, "PerformanceFeeHooks");
        address owner = Ownable(hook).owner();
        vm.startPrank(owner);
        IFeeHooks(hook).setPerformanceFee(_performanceFee);
        vm.stopPrank();
    }
}