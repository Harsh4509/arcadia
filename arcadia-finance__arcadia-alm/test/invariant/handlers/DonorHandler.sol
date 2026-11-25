/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { INonfungiblePositionManager } from "../../utils/fixtures/metadex/interfaces/INonfungiblePositionManager.sol";

/**
 * @notice Sends "ALMCore" tokens, shares, liquidity and positions it never asked for, for the invariant suite.
 */
contract DonorHandler is BaseHandler {
    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    INonfungiblePositionManager internal immutable POSITION_MANAGER;
    ERC20Mock internal immutable TOKEN0;
    ERC20Mock internal immutable TOKEN1;
    address internal immutable REWARD_TOKEN;

    uint256[] internal tokenIds;
    uint256 internal nextTokenId;

    uint256 public ghostDonated0;
    uint256 public ghostDonated1;
    uint256 public ghostDonatedReward;
    uint256 public ghostDonatedTokenIds;
    // The aLP holders sent the core.
    uint256 public ghostDonatedShares;
    // The state-changing core calls that went through.
    uint256 public ghostCheckpoints;
    // The liquidity donors added to each position of the core.
    uint256 public ghostDonatedLiquidity;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ALMCoreHandler coreHandler,
        INonfungiblePositionManager positionManager,
        ERC20Mock token0,
        ERC20Mock token1,
        address rewardToken
    ) {
        ALM_CORE = almCore;
        CORE_HANDLER = coreHandler;
        POSITION_MANAGER = positionManager;
        TOKEN0 = token0;
        TOKEN1 = token1;
        REWARD_TOKEN = rewardToken;
    }

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function stageTokenId(uint256 tokenId) external {
        tokenIds.push(tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 selector) {
        selector = this.onERC721Received.selector;
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function donateToken0(uint256 amount) external countCall(this.donateToken0.selector) {
        uint256 balance = FixedPointMathLib.max(TOKEN0.balanceOf(address(ALM_CORE)), ghostDonated0);
        if (balance + 2 > Constants.MAX_FUZZED_AMOUNT) return;
        amount = bound(amount, 1, (Constants.MAX_FUZZED_AMOUNT - balance) / 2);

        TOKEN0.mint(address(ALM_CORE), amount);
        ghostDonated0 += amount;
    }

    function donateToken1(uint256 amount) external countCall(this.donateToken1.selector) {
        uint256 balance = FixedPointMathLib.max(TOKEN1.balanceOf(address(ALM_CORE)), ghostDonated1);
        if (balance + 2 > Constants.MAX_FUZZED_AMOUNT) return;
        amount = bound(amount, 1, (Constants.MAX_FUZZED_AMOUNT - balance) / 2);

        TOKEN1.mint(address(ALM_CORE), amount);
        ghostDonated1 += amount;
    }

    function donateRewardToken(uint256 amount) external countCall(this.donateRewardToken.selector) {
        uint256 balance = ERC20Mock(REWARD_TOKEN).balanceOf(address(ALM_CORE));
        uint256 donated = FixedPointMathLib.max(balance, ghostDonatedReward);
        if (donated + 2 > Constants.MAX_FUZZED_AMOUNT) return;
        amount = bound(amount, 1, (Constants.MAX_FUZZED_AMOUNT - donated) / 2);

        deal(REWARD_TOKEN, address(ALM_CORE), balance + amount);
        ghostDonatedReward += amount;
    }

    function donateTokenId() external countCall(this.donateTokenId.selector) {
        if (nextTokenId == tokenIds.length) return;

        try POSITION_MANAGER.transferFrom(address(this), address(ALM_CORE), tokenIds[nextTokenId]) {
            ++nextTokenId;
            ++ghostDonatedTokenIds;
        } catch (bytes memory reason) {
            _recordRevert(this.donateTokenId.selector, reason);
        }
    }

    function donateShares(uint256 actorSeed, uint256 shares) external countCall(this.donateShares.selector) {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        uint256 balance = ALM_CORE.balanceOf(actor);
        if (balance == 0) return;
        shares = bound(shares, 1, balance);
        CORE_HANDLER.trackFairShares();
        CORE_HANDLER.watchPending();

        vm.prank(actor);
        try ALM_CORE.transfer(address(ALM_CORE), shares) {
            ghostCheckpoints++;
            ghostDonatedShares += shares;
        } catch (bytes memory reason) {
            _recordRevert(this.donateShares.selector, reason);
        }

        CORE_HANDLER.countPendingMoves(actor, actor);
    }

    function donateLiquidity(uint256 indexSeed, uint256 amount0, uint256 amount1)
        external
        countCall(this.donateLiquidity.selector)
    {
        uint256 length = ALM_CORE.getRangesLength();
        if (length == 0) return;
        uint256 tokenId = ALM_CORE.getRange(bound(indexSeed, 0, length - 1)).unstakedTokenId;
        amount0 = bound(amount0, 0, Constants.MAX_FUZZED_AMOUNT / 2);
        amount1 = bound(amount1, 0, Constants.MAX_FUZZED_AMOUNT / 2);
        TOKEN0.mint(address(this), amount0);
        TOKEN1.mint(address(this), amount1);
        TOKEN0.approve(address(POSITION_MANAGER), amount0);
        TOKEN1.approve(address(POSITION_MANAGER), amount1);

        try POSITION_MANAGER.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: vm.getBlockTimestamp()
            })
        ) returns (
            uint128 liquidity, uint256, uint256
        ) {
            ghostDonatedLiquidity += liquidity;
        } catch (bytes memory reason) {
            _recordRevert(this.donateLiquidity.selector, reason);
        }
    }
}
