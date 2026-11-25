/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";

/**
 * @notice Drives the factory's governance of "ALMCore" and calls its privileged surface from unprivileged accounts.
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GovernanceHandler is BaseHandler {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The longest minimum time between two plans, a day.
    uint32 public constant MAX_MIN_PLAN_INTERVAL = 1 days;
    // The highest maxShortfallBps a realistic draw takes, the 1% a plan may lose at most in production.
    uint256 public constant MAX_REALISTIC_SHORTFALL_BPS = 100;
    // The highest maxSwapCostBps a realistic draw takes, below the 55 bps gas bound of audit doc 6.4.
    uint256 public constant MAX_REALISTIC_SWAP_COST_BPS = 54;
    // The narrowest deviation band a realistic draw takes, 0.1% of sqrt price or about 0.2% of price.
    uint256 public constant MIN_REALISTIC_DEVIATION = 1e15;
    // The widest deviation band a realistic draw takes, 1% of sqrt price or about 2% of price.
    uint256 public constant MAX_REALISTIC_DEVIATION = 1e16;
    // One in this many pause draws pauses, so a run spends most of its calls unpaused.
    uint256 public constant PAUSE_ODDS = 4;
    // The most a realistic raise multiplies the total cap or the supply by.
    uint256 public constant MAX_CAP_GROWTH = 2;
    // The cap moves, by the setter they call.
    uint256 internal constant CAP_SET_PER_USER = 0;
    uint256 internal constant CAP_LOWER_TOTAL = 1;
    uint256 internal constant CAP_RAISE_TOTAL = 2;
    uint256 internal constant CAP_LOWER_PER_USER = 3;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    address internal immutable FACTORY;
    // The holder of the factory's steward role.
    address internal immutable STEWARD;

    // The privileged calls an unprivileged caller made that the core accepted.
    uint256 public ghostUnauthorizedAccepted;
    // The state-changing core calls that went through.
    uint256 public ghostCheckpoints;
    // The governance moves that went through, by kind.
    uint256 public ghostCapRaises;
    uint256 public ghostRangeCapMoves;
    uint256 public ghostPlanLimitMoves;
    uint256 public ghostDeviationMoves;
    // The lower-only cap calls to a value at or above the cap that went through, and those refused for another reason.
    uint256 public ghostNonLoweringAccepted;
    uint256 public ghostNonLoweringWrongReasons;
    uint256 public ghostNonLoweringTried;
    // The ranges the core held when the range cap was last set, which a cap below them leaves in place.
    uint256 public ghostRangesAtCapMove;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(ALMCoreExtension almCore, ALMCoreHandler coreHandler, address factory, address steward) {
        ALM_CORE = almCore;
        CORE_HANDLER = coreHandler;
        FACTORY = factory;
        STEWARD = steward;
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function pause(uint256 seed) external countCall(this.pause.selector) advanceBlock {
        if (seed % PAUSE_ODDS != 0) return;
        CORE_HANDLER.trackFairShares();
        vm.prank(STEWARD);
        try ALMFactory(FACTORY).pause(address(ALM_CORE)) {
            ghostCheckpoints++;
        } catch (bytes memory reason) {
            _recordRevert(this.pause.selector, reason);
        }
    }

    function unpause() external countCall(this.unpause.selector) advanceBlock {
        CORE_HANDLER.trackFairShares();
        vm.prank(STEWARD);
        try ALMFactory(FACTORY).unpause(address(ALM_CORE)) {
            ghostCheckpoints++;
        } catch (bytes memory reason) {
            _recordRevert(this.unpause.selector, reason);
        }
    }

    function setPerUserCap(uint256 newPerUserCap) external countCall(this.setPerUserCap.selector) advanceBlock {
        uint256 totalCap = ALM_CORE.totalCap_();
        newPerUserCap = bound(newPerUserCap, FixedPointMathLib.min(_highestCapBalance(), totalCap), totalCap);
        _setCap(CAP_SET_PER_USER, newPerUserCap, this.setPerUserCap.selector);
    }

    function lowerTotalCap(uint256 newTotalCap) external countCall(this.lowerTotalCap.selector) advanceBlock {
        uint256 totalCap = ALM_CORE.totalCap_();
        if (totalCap == 0) return;
        newTotalCap = bound(newTotalCap, FixedPointMathLib.min(ALM_CORE.totalSupply(), totalCap - 1), totalCap - 1);
        _setCap(CAP_LOWER_TOTAL, newTotalCap, this.lowerTotalCap.selector);
    }

    function raiseTotalCap(uint256 newTotalCap) external countCall(this.raiseTotalCap.selector) advanceBlock {
        uint256 supply = ALM_CORE.totalSupply();
        newTotalCap = bound(newTotalCap, supply, MAX_CAP_GROWTH * FixedPointMathLib.max(supply, ALM_CORE.totalCap_()));
        _setCap(CAP_RAISE_TOTAL, newTotalCap, this.raiseTotalCap.selector);
    }

    function lowerPerUserCap(uint256 newPerUserCap) external countCall(this.lowerPerUserCap.selector) advanceBlock {
        uint256 perUserCap = ALM_CORE.perUserCap_();
        if (perUserCap == 0) return;
        newPerUserCap =
            bound(newPerUserCap, FixedPointMathLib.min(_highestCapBalance(), perUserCap - 1), perUserCap - 1);
        _setCap(CAP_LOWER_PER_USER, newPerUserCap, this.lowerPerUserCap.selector);
    }

    function setCapWide(uint256 kind, uint256 newCap) external countCall(this.setCapWide.selector) advanceBlock {
        kind = bound(kind, CAP_SET_PER_USER, CAP_LOWER_PER_USER);
        uint256 cap = kind == CAP_LOWER_PER_USER ? ALM_CORE.perUserCap_() : ALM_CORE.totalCap_();
        if (kind == CAP_SET_PER_USER) {
            newCap = bound(newCap, 0, cap);
        } else if (kind == CAP_RAISE_TOTAL) {
            newCap = bound(newCap, ALM_CORE.totalSupply(), type(uint128).max);
        } else {
            if (cap == 0) return;
            newCap = bound(newCap, 0, cap - 1);
        }
        _setCap(kind, newCap, this.setCapWide.selector);
    }

    function setCapExempt(uint256 actorSeed, bool exempt) external countCall(this.setCapExempt.selector) advanceBlock {
        address actor = CORE_HANDLER.actorAt(actorSeed);

        CORE_HANDLER.trackFairShares();
        vm.prank(FACTORY);
        try ALM_CORE.setCapExempt(actor, exempt) {
            ghostCheckpoints++;
        } catch (bytes memory reason) {
            _recordRevert(this.setCapExempt.selector, reason);
        }
    }

    function lowerCapsToNoLower(uint256 newTotalCap, uint256 newPerUserCap)
        external
        countCall(this.lowerCapsToNoLower.selector)
        advanceBlock
    {
        newTotalCap = bound(newTotalCap, ALM_CORE.totalCap_(), type(uint256).max);
        newPerUserCap = bound(newPerUserCap, ALM_CORE.perUserCap_(), type(uint256).max);

        CORE_HANDLER.trackFairShares();
        ghostNonLoweringTried += 2;
        vm.prank(FACTORY);
        try ALM_CORE.lowerTotalCap(newTotalCap) {
            ghostCheckpoints++;
            ghostNonLoweringAccepted++;
        } catch (bytes memory reason) {
            _recordRevert(this.lowerCapsToNoLower.selector, reason);
            if (_selectorOf(reason) != ALMAdminExtension.TotalCapNotLowered.selector) ghostNonLoweringWrongReasons++;
        }
        vm.prank(FACTORY);
        try ALM_CORE.lowerPerUserCap(newPerUserCap) {
            ghostCheckpoints++;
            ghostNonLoweringAccepted++;
        } catch (bytes memory reason) {
            _recordRevert(this.lowerCapsToNoLower.selector, reason);
            if (_selectorOf(reason) != ALMAdminExtension.PerUserCapNotLowered.selector) {
                ghostNonLoweringWrongReasons++;
            }
        }
    }

    function setRangeCap(uint256 newRangeCap) external countCall(this.setRangeCap.selector) advanceBlock {
        newRangeCap = bound(newRangeCap, 0, ConfigLib.MAX_RANGE_CAP);

        CORE_HANDLER.trackFairShares();
        vm.prank(FACTORY);
        try ALM_CORE.setRangeCap(uint8(newRangeCap)) {
            ghostCheckpoints++;
            ghostRangeCapMoves++;
            ghostRangesAtCapMove = ALM_CORE.getRangesLength();
        } catch (bytes memory reason) {
            _recordRevert(this.setRangeCap.selector, reason);
        }
    }

    function setPlanLimits(uint256 maxShortfallBps, uint256 maxSwapCostBps, uint256 minPlanInterval)
        external
        countCall(this.setPlanLimits.selector)
        advanceBlock
    {
        uint256 minSwapCostBps = IMetadexCLPool(ALM_CORE.pool_()).fee() / 100 + 1;
        maxShortfallBps = bound(maxShortfallBps, 0, MAX_REALISTIC_SHORTFALL_BPS);
        maxSwapCostBps =
            bound(maxSwapCostBps, minSwapCostBps, FixedPointMathLib.max(minSwapCostBps, MAX_REALISTIC_SWAP_COST_BPS));
        _setPlanLimits(maxShortfallBps, maxSwapCostBps, minPlanInterval, this.setPlanLimits.selector);
    }

    function setPlanLimitsWide(uint256 maxShortfallBps, uint256 maxSwapCostBps, uint256 minPlanInterval)
        external
        countCall(this.setPlanLimitsWide.selector)
        advanceBlock
    {
        maxShortfallBps = bound(maxShortfallBps, 0, ConfigLib.BPS_DENOMINATOR);
        maxSwapCostBps = bound(maxSwapCostBps, 0, ConfigLib.BPS_DENOMINATOR - 1);
        _setPlanLimits(maxShortfallBps, maxSwapCostBps, minPlanInterval, this.setPlanLimitsWide.selector);
    }

    function setDeviation(
        uint256 twapWindow,
        uint256 maxSpotFromTwap,
        uint256 maxSpotFromTrusted,
        uint256 maxTwapFromTrusted
    ) external countCall(this.setDeviation.selector) advanceBlock {
        maxSpotFromTwap = bound(maxSpotFromTwap, MIN_REALISTIC_DEVIATION, MAX_REALISTIC_DEVIATION);
        maxSpotFromTrusted = bound(maxSpotFromTrusted, MIN_REALISTIC_DEVIATION, MAX_REALISTIC_DEVIATION);
        maxTwapFromTrusted = bound(maxTwapFromTrusted, MIN_REALISTIC_DEVIATION, MAX_REALISTIC_DEVIATION);
        _setDeviation(twapWindow, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted, this.setDeviation.selector);
    }

    function setDeviationWide(
        uint256 twapWindow,
        uint256 maxSpotFromTwap,
        uint256 maxSpotFromTrusted,
        uint256 maxTwapFromTrusted
    ) external countCall(this.setDeviationWide.selector) advanceBlock {
        maxSpotFromTwap = bound(maxSpotFromTwap, 0, type(uint64).max);
        maxSpotFromTrusted = bound(maxSpotFromTrusted, 0, type(uint64).max);
        maxTwapFromTrusted = bound(maxTwapFromTrusted, 0, type(uint64).max);
        _setDeviation(
            twapWindow, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted, this.setDeviationWide.selector
        );
    }

    function callUnauthorized(uint256 callerSeed, uint256 pick, uint256 amount)
        external
        countCall(this.callUnauthorized.selector)
        advanceBlock
    {
        address caller = CORE_HANDLER.actorAt(callerSeed);
        bytes[] memory callDatas = _privilegedCallDatas(caller, amount);

        CORE_HANDLER.trackFairShares();
        vm.prank(caller);
        (bool success, bytes memory reason) = address(ALM_CORE).call(callDatas[bound(pick, 0, callDatas.length - 1)]);
        if (success) {
            ghostCheckpoints++;
            ghostUnauthorizedAccepted++;
        } else {
            _recordRevert(this.callUnauthorized.selector, reason);
        }
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _afterAction() internal override {
        CORE_HANDLER.checkMonotone();
    }

    function _setCap(uint256 kind, uint256 newCap, bytes4 selector) internal {
        CORE_HANDLER.trackFairShares();
        vm.prank(FACTORY);
        (bool success, bytes memory reason) = address(ALM_CORE)
            .call(
                kind == CAP_SET_PER_USER
                    ? abi.encodeCall(ALMCore.setPerUserCap, (newCap))
                    : kind == CAP_LOWER_TOTAL
                        ? abi.encodeCall(ALMCore.lowerTotalCap, (newCap))
                        : kind == CAP_RAISE_TOTAL
                            ? abi.encodeCall(ALMCore.setTotalCap, (newCap))
                            : abi.encodeCall(ALMCore.lowerPerUserCap, (newCap))
            );
        if (!success) return _recordRevert(selector, reason);
        ghostCheckpoints++;
        if (kind == CAP_RAISE_TOTAL) ghostCapRaises++;
    }

    function _highestCapBalance() internal view returns (uint256 highest) {
        for (uint256 i; i < CORE_HANDLER.actorsLength(); ++i) {
            address actor = CORE_HANDLER.actorAt(i);
            highest = FixedPointMathLib.max(
                highest, ALM_CORE.balanceOf(actor) + ALM_CORE.claimableSharesOf_(actor) + ALM_CORE.pendingShares_(actor)
            );
        }
    }

    function _setPlanLimits(uint256 maxShortfallBps, uint256 maxSwapCostBps, uint256 minPlanInterval, bytes4 selector)
        internal
    {
        minPlanInterval = bound(minPlanInterval, 0, MAX_MIN_PLAN_INTERVAL);

        CORE_HANDLER.trackFairShares();
        vm.prank(FACTORY);
        try ALM_CORE.setPlanLimits(uint16(maxShortfallBps), uint16(maxSwapCostBps), uint32(minPlanInterval)) {
            ghostCheckpoints++;
            ghostPlanLimitMoves++;
        } catch (bytes memory reason) {
            _recordRevert(selector, reason);
        }
    }

    function _setDeviation(
        uint256 twapWindow,
        uint256 maxSpotFromTwap,
        uint256 maxSpotFromTrusted,
        uint256 maxTwapFromTrusted,
        bytes4 selector
    ) internal {
        twapWindow = bound(twapWindow, 1, Constants.TWAP_WINDOW);

        CORE_HANDLER.trackFairShares();
        vm.prank(FACTORY);
        try ALM_CORE.setDeviation(uint32(twapWindow), maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted) {
            ghostCheckpoints++;
            ghostDeviationMoves++;
        } catch (bytes memory reason) {
            _recordRevert(selector, reason);
        }
    }

    function _privilegedCallDatas(address account, uint256 amount) internal view returns (bytes[] memory callDatas) {
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        callDatas = new bytes[](21);
        callDatas[0] = abi.encodeCall(ALMCore.execute, (new bytes(0), new bytes[](0), sqrtPriceX96));
        callDatas[1] = abi.encodeCall(ALMCore.setRangeCap, (uint8(amount)));
        callDatas[2] = abi.encodeCall(ALMCore.setPerUserCap, (amount));
        callDatas[3] = abi.encodeCall(ALMCore.setTotalCap, (amount));
        callDatas[4] = abi.encodeCall(ALMCore.lowerTotalCap, (amount));
        callDatas[5] = abi.encodeCall(ALMCore.setPlanLimits, (uint16(amount), uint16(amount), uint32(amount)));
        callDatas[6] = abi.encodeCall(ALMCore.setDeviation, (uint32(amount), amount, amount, amount));
        callDatas[7] = amount % 2 == 1 ? abi.encodeCall(ALMCore.pause, ()) : abi.encodeCall(ALMCore.unpause, ());
        callDatas[8] = abi.encodeCall(ALMCore.setProtocolFees, (uint16(amount), uint16(amount), account));
        callDatas[9] = abi.encodeCall(ALMCore.setCapExempt, (account, amount % 2 == 1));
        callDatas[10] = abi.encodeCall(ALMCore.recordDepositRequest, (account, amount));
        callDatas[11] = abi.encodeCall(ALMCore.recordRedeemRequest, (account, account, account, amount));
        callDatas[12] = abi.encodeCall(ALMCore.cancelDepositRequest, (amount, account, account));
        callDatas[13] = abi.encodeCall(ALMCore.cancelRedeemRequest, (amount, account, account));
        callDatas[14] = abi.encodeCall(ALMCore.claimDepositRequest, (account, amount, amount, account));
        callDatas[15] = abi.encodeCall(ALMCore.claimRedeemRequest, (account, amount, amount, account));
        callDatas[16] = abi.encodeCall(ALMCore.setOperator, (account, account, amount % 2 == 1));
        callDatas[17] = abi.encodeCall(ALMCore.seed, (amount, amount, amount, account));
        callDatas[18] = abi.encodeCall(ALMCore.trustedBurn, (amount, account, account, account));
        callDatas[19] = abi.encodeCall(ALMCore.lowerPerUserCap, (amount));
        callDatas[20] = abi.encodeCall(ALMCore.checkpoint, ());
    }
}
