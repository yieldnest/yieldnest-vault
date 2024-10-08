// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./YnAsset.sol";
import "./IRateProvider.sol";


contract AssetPool is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ASSET_ADMIN_ROLE = keccak256("ASSET_ADMIN_ROLE");

    struct Asset {
        bool active;
    }

    YnAsset public ynAsset;
    IRateProvider public rateProvider;
    mapping(address => Asset) public assets;
    address[] public assetList;

    function initialize(YnAsset _ynAsset, IRateProvider _rateProvider) public initializer {
        ynAsset = _ynAsset;
        rateProvider = _rateProvider;
    }

    function addAsset(IERC20 _token) external onlyRole(ASSET_ADMIN_ROLE) {
        require(!assets[address(_token)].active, "Asset already added");
        assets[address(_token)] = Asset(true);
        assetList.push(address(_token));
    }

    function deposit(address asset, uint256 _amount, address _receiver) external {
        require(assets[asset].active, "Asset not supported");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);
        
        uint256 ynAssetAmount = rateProvider.convert(asset, _amount);
        ynAsset.mint(_receiver, ynAssetAmount);
    }
}
