/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { PositionManagerLogic } from "../../../src/core/libraries/logic/PositionManagerLogic.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { TokenDelta } from "../../../src/core/types/TokenDelta.sol";

contract PositionManagerLogicExtension {
    using SafeTransferLib for address;

    address internal immutable POSITION_MANAGER;
    address internal immutable TOKEN0;
    address internal immutable TOKEN1;
    int24 internal immutable TICK_SPACING;

    constructor(address positionManager, address token0, address token1, int24 tickSpacing) {
        POSITION_MANAGER = positionManager;
        TOKEN0 = token0;
        TOKEN1 = token1;
        TICK_SPACING = tickSpacing;
        token0.safeApproveWithRetry(positionManager, type(uint256).max);
        token1.safeApproveWithRetry(positionManager, type(uint256).max);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 selector) {
        selector = this.onERC721Received.selector;
    }

    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 tokenId, uint128 liquidity, TokenDelta delta) {
        IMetadexCLPositionManager.MintParams memory params;
        (params.token0, params.token1, params.tickSpacing, params.tickLower, params.tickUpper) =
        (TOKEN0, TOKEN1, TICK_SPACING, tickLower, tickUpper);
        (params.amount0Desired, params.amount1Desired, params.amount0Min, params.amount1Min) =
        (amount0Desired, amount1Desired, amount0Min, amount1Min);
        (tokenId, liquidity, delta) = PositionManagerLogic.mint(POSITION_MANAGER, params);
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint128 liquidity, TokenDelta delta) {
        IMetadexCLPositionManager.IncreaseLiquidityParams memory params;
        (params.tokenId, params.amount0Desired, params.amount1Desired, params.amount0Min, params.amount1Min) =
        (tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min);
        (liquidity, delta) = PositionManagerLogic.increaseLiquidity(POSITION_MANAGER, params);
    }

    function decreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min)
        external
        returns (TokenDelta principal)
    {
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
        (params.tokenId, params.liquidity, params.amount0Min, params.amount1Min) =
        (tokenId, liquidity, amount0Min, amount1Min);
        principal = PositionManagerLogic.decreaseLiquidity(POSITION_MANAGER, params);
    }

    function collect(uint256 tokenId) external returns (TokenDelta gross) {
        IMetadexCLPositionManager.CollectParams memory params;
        params.tokenId = tokenId;
        gross = PositionManagerLogic.collect(POSITION_MANAGER, params);
    }

    function decreaseLiquidityAndCollect(uint256 tokenId, uint128 liquidity)
        external
        returns (TokenDelta principal, TokenDelta fees)
    {
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
        (params.tokenId, params.liquidity) = (tokenId, liquidity);
        (principal, fees) = PositionManagerLogic.decreaseLiquidityAndCollect(POSITION_MANAGER, params);
    }
}
