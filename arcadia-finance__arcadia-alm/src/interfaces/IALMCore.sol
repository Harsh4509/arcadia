/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { IExtsload } from "@uniswap/v4-core/src/interfaces/IExtsload.sol";
import { IExttload } from "@uniswap/v4-core/src/interfaces/IExttload.sol";

interface IALMCore is IExtsload, IExttload {
    function balanceOf(address account) external view returns (uint256 shares);
    function cancelDepositRequest(uint256 requestId, address controller, address receiver)
        external
        returns (uint256 assets);
    function cancelRedeemRequest(uint256 requestId, address controller, address receiver)
        external
        returns (uint256 shares);
    function claimDepositRequest(address controller, uint256 assets, uint256 maxShares, address receiver)
        external
        returns (uint256 shares);
    function claimRedeemRequest(address controller, uint256 shares, uint256 maxAssets, address receiver)
        external
        returns (uint256 assets);
    function getRewardOwed(address account) external view returns (uint256 owed);
    function getUnstakedPositions()
        external
        view
        returns (uint256 fees0, uint256 fees1, uint128[] memory positionLiquidity);
    function mint(uint256 shares, address receiver) external returns (uint256 amount0, uint256 amount1);
    function recordDepositRequest(address controller, uint256 assets) external;
    function recordRedeemRequest(address controller, address owner, address caller, uint256 shares) external;
    function setOperator(address controller, address operator, bool approved) external returns (bool success);
    function skim() external returns (uint256 amount0, uint256 amount1);
    function totalSupply() external view returns (uint256 shares);
    function trustedBurn(uint256 shares, address receiver, address owner, address caller)
        external
        returns (uint256 amount0, uint256 amount1);
}
