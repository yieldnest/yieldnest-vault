// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;
import {IStrategy} from "src/interface/IStrategy.sol";
import {IERC20, ERC20} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {ERC4626Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

interface ILido is IERC20 {
    function submit(address _referral) external payable returns (uint256);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}


interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}

contract StETHBuffer is ERC4626Upgradeable {

    ICurvePool curvePool;

    ILido public immutable stETH;
    IWETH public immutable weth;

    constructor(address _stETH, address _weth) {
        stETH = ILido(_stETH);
        weth = IWETH(_weth);
    }

    function initialize(address _curvePool) public initializer {
        __ERC4626_init(IERC20(weth));
        __ERC20_init("StETH Buffer", "stBUFF");
        curvePool = ICurvePool(_curvePool);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        
        // Transfer WETH from sender
        weth.transferFrom(msg.sender, address(this), assets);

        // Unwrap WETH to ETH
        weth.withdraw(assets);
        // Calculate shares from assets
        uint256 shares = previewDeposit(assets);

        // Submit ETH to Lido to get stETH
        stETH.submit{value: assets}(address(0));

        // Mint shares to receiver
        _mint(receiver, shares);

        return shares;
    }

    function totalAssets() public view override returns (uint256) {
        return stETH.balanceOf(address(this));
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        // Swap stETH for ETH in Curve pool
        stETH.approve(address(curvePool), assets);
        uint256 ethReceived = curvePool.exchange(1, 0, assets, 0);

        // Wrap ETH to WETH and transfer to receiver
        weth.deposit{value: ethReceived}();
        weth.transfer(receiver, ethReceived);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    receive() external payable {}
}
