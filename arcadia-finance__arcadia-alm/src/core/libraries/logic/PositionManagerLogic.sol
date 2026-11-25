/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLPositionManager } from "../../../interfaces/IMetadexCLPositionManager.sol";
import { TokenDelta, TokenDeltaLib } from "../../types/TokenDelta.sol";

/**
 * @title Position Manager Logic.
 * @author Pragma Labs
 * @notice Moves the core's pool tokens into and out of Metadex positions.
 */
// forge-lint: disable-next-item(calls-loop, unused-return)
library PositionManagerLogic {
    using FixedPointMathLib for uint256;
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                            POSITION MANAGER
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a fresh token id at a tick range.
     * @param positionManager The Metadex CL position manager.
     * @param params The mint parameters, without recipient and deadline.
     * @return tokenId The minted token id.
     * @return liquidity The liquidity minted.
     * @return delta The token amounts the mint consumed.
     */
    function mint(address positionManager, IMetadexCLPositionManager.MintParams memory params)
        internal
        returns (uint256 tokenId, uint128 liquidity, TokenDelta delta)
    {
        (params.recipient, params.deadline) = (address(this), block.timestamp);
        uint256 amount0;
        uint256 amount1;
        (tokenId, liquidity, amount0, amount1) = IMetadexCLPositionManager(positionManager).mint(params);

        delta = TokenDeltaLib.fromAmounts(amount0, amount1).neg();
    }

    /**
     * @notice Adds liquidity to a token id.
     * @param positionManager The Metadex CL position manager.
     * @param params The increase parameters, without deadline.
     * @return liquidity The liquidity added.
     * @return delta The token amounts the add consumed.
     */
    function increaseLiquidity(address positionManager, IMetadexCLPositionManager.IncreaseLiquidityParams memory params)
        internal
        returns (uint128 liquidity, TokenDelta delta)
    {
        params.deadline = block.timestamp;
        uint256 amount0;
        uint256 amount1;
        (liquidity, amount0, amount1) = IMetadexCLPositionManager(positionManager).increaseLiquidity(params);

        delta = TokenDeltaLib.fromAmounts(amount0, amount1).neg();
    }

    /**
     * @notice Removes liquidity from a token id, leaving the released tokens owed to it.
     * @param positionManager The Metadex CL position manager.
     * @param params The decrease parameters, without deadline.
     * @return principal The token amounts released.
     */
    function decreaseLiquidity(address positionManager, IMetadexCLPositionManager.DecreaseLiquidityParams memory params)
        internal
        returns (TokenDelta principal)
    {
        params.deadline = block.timestamp;
        (uint256 amount0, uint256 amount1) = IMetadexCLPositionManager(positionManager).decreaseLiquidity(params);

        principal = TokenDeltaLib.fromAmounts(amount0, amount1);
    }

    /**
     * @notice Collects everything a token id is owed.
     * @param positionManager The Metadex CL position manager.
     * @param params The collect parameters, without recipient and maximums.
     * @return gross The token amounts collected, principal and accrued fees together.
     */
    function collect(address positionManager, IMetadexCLPositionManager.CollectParams memory params)
        internal
        returns (TokenDelta gross)
    {
        (params.recipient, params.amount0Max, params.amount1Max) = (address(this), type(uint128).max, type(uint128).max);
        (uint256 amount0, uint256 amount1) = IMetadexCLPositionManager(positionManager).collect(params);

        gross = TokenDeltaLib.fromAmounts(amount0, amount1);
    }

    /**
     * @notice Removes liquidity from a token id and collects it.
     * @param positionManager The Metadex CL position manager.
     * @param params The decrease parameters, without deadline.
     * @return principal The token amounts released.
     * @return fees The accrued fees collected, before the protocol share.
     */
    function decreaseLiquidityAndCollect(
        address positionManager,
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params
    ) internal returns (TokenDelta principal, TokenDelta fees) {
        principal = decreaseLiquidity(positionManager, params);
        IMetadexCLPositionManager.CollectParams memory collectParams;
        collectParams.tokenId = params.tokenId;
        fees = collect(positionManager, collectParams).add(principal.neg());
    }
}
