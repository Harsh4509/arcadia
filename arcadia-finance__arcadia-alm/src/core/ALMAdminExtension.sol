/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { BaseExtension } from "./abstracts/base/BaseExtension.sol";
import { CalldataLogic } from "./libraries/logic/CalldataLogic.sol";
import { CLMath } from "../shared/libraries/math/CLMath.sol";
import { Config, RewardAccount, State } from "./types/State.sol";
import { ConfigLib } from "./libraries/state/ConfigLib.sol";
import { CoreImmutables } from "./types/CoreImmutables.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { PoolLogic } from "../shared/libraries/logic/PoolLogic.sol";
import { PoolTokensLib } from "./libraries/state/PoolTokensLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { TokenAmounts, TokenDelta, TokenDeltaLib } from "./types/TokenDelta.sol";

/**
 * @title ALM Admin Extension.
 * @author Pragma Labs
 * @notice The governance, maintenance and emissions claim entry points of a core.
 */
// forge-lint: disable-next-item(arbitrary-send-eth, reentrancy-events)
contract ALMAdminExtension is BaseExtension {
    using FixedPointMathLib for uint256;
    using PoolTokensLib for TokenAmounts;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The aLP shares of the first mint that are minted to address(1), where they stay.
    uint256 internal constant DEAD_SHARES = 1e6;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error AlreadySeeded();
    error InvalidAmounts();
    error InvalidFee();
    error InvalidMaxShortfall();
    error InvalidMaxSwapCost();
    error InvalidRangeCap();
    error InvalidShares();
    error InvalidTwapWindow();
    error OnlyVault();
    error PerUserCapNotLowered();
    error RewardsPending();
    error TotalCapNotLowered();

    /* //////////////////////////////////////////////////////////////
                               GOVERNANCE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the maximum number of ranges.
     * @param newRangeCap The new range cap.
     */
    function setRangeCap(uint8 newRangeCap) external onlyFactory {
        // Checks.
        if (newRangeCap > ConfigLib.MAX_RANGE_CAP) revert InvalidRangeCap();

        // Update State.
        _state().config.rangeCap = newRangeCap;

        emit RangeCapSet(newRangeCap);
    }

    /**
     * @notice Sets the most aLP any one account may hold, counting its requests.
     * @param newPerUserCap The new per user cap.
     */
    function setPerUserCap(uint256 newPerUserCap) external onlyFactory {
        // Update State.
        _setPerUserCap(_state().config, newPerUserCap);
    }

    /**
     * @notice Lowers the most aLP any one account may hold, counting its requests.
     * @param newPerUserCap The new per user cap.
     */
    function lowerPerUserCap(uint256 newPerUserCap) external onlyFactory {
        // Checks.
        Config storage config = _state().config;
        if (newPerUserCap >= config.perUserCap) revert PerUserCapNotLowered();

        // Update State.
        _setPerUserCap(config, newPerUserCap);
    }

    /**
     * @notice Writes the most aLP any one account may hold.
     * @param config The governance parameters.
     * @param newPerUserCap The new per user cap.
     */
    function _setPerUserCap(Config storage config, uint256 newPerUserCap) internal {
        // Update State.
        config.perUserCap = SafeCastLib.toUint128(newPerUserCap);

        emit PerUserCapSet(newPerUserCap);
    }

    /**
     * @notice Exempts an account from the per user cap, or lifts the exemption.
     * @param account The account.
     * @param exempt True to exempt, false to lift the exemption.
     */
    function setCapExempt(address account, bool exempt) external onlyFactory {
        // Update State.
        _state().share.isExempt[account] = exempt;

        emit CapExemptSet(account, exempt);
    }

    /**
     * @notice Sets the maximum aLP supply.
     * @param newTotalCap The new total cap.
     */
    function setTotalCap(uint256 newTotalCap) external onlyFactory {
        // Update State.
        _setTotalCap(_state().config, newTotalCap);
    }

    /**
     * @notice Lowers the maximum aLP supply.
     * @param newTotalCap The new total cap.
     */
    function lowerTotalCap(uint256 newTotalCap) external onlyFactory {
        // Checks.
        Config storage config = _state().config;
        if (newTotalCap >= config.totalCap) revert TotalCapNotLowered();

        // Update State.
        _setTotalCap(config, newTotalCap);
    }

    /**
     * @notice Writes the maximum aLP supply.
     * @param config The governance parameters.
     * @param newTotalCap The new total cap.
     */
    function _setTotalCap(Config storage config, uint256 newTotalCap) internal {
        // Update State.
        config.totalCap = SafeCastLib.toUint128(newTotalCap);

        emit TotalCapSet(newTotalCap);
    }

    /**
     * @notice Sets the max shortfall per plan, the max swap cost and the minimum time between plans.
     * @param newMaxShortfallBps The value per share a plan may lose against its trusted price.
     * @param newMaxSwapCostBps The value a swap may lose against the pool's spot price at the start of its plan.
     * @param newMinPlanInterval The minimum time between two plans, in seconds.
     * @dev At the real price a plan may lose about maxShortfallBps plus twice maxSpotFromTrusted.
     */
    function setPlanLimits(uint16 newMaxShortfallBps, uint16 newMaxSwapCostBps, uint32 newMinPlanInterval)
        external
        onlyFactory
    {
        // Checks.
        if (newMaxShortfallBps > ConfigLib.BPS_DENOMINATOR) revert InvalidMaxShortfall();
        if (newMaxSwapCostBps > ConfigLib.BPS_DENOMINATOR) revert InvalidMaxSwapCost();

        // Update State.
        Config storage config = _state().config;
        config.maxShortfallBps = newMaxShortfallBps;
        config.maxSwapCostBps = newMaxSwapCostBps;
        config.minPlanInterval = newMinPlanInterval;

        emit PlanLimitsSet(newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    /**
     * @notice Blocks minting and the keeper steps that add liquidity, swap or settle deposits.
     */
    function pause() external onlyFactory {
        // Update State.
        _state().config.paused = true;

        emit PausedSet(true);
    }

    /**
     * @notice Lifts the pause.
     */
    function unpause() external onlyFactory {
        // Update State.
        _state().config.paused = false;

        emit PausedSet(false);
    }

    /**
     * @notice Sets the TWAP reference window and the three price bands.
     * @param newTwapWindow The TWAP window in seconds.
     * @param newMaxSpotFromTwap The 1e18-scaled ratio band of the spot sqrt price around the TWAP.
     * @param newMaxSpotFromTrusted The 1e18-scaled ratio band of the spot sqrt price around a plan's price.
     * @param newMaxTwapFromTrusted The 1e18-scaled ratio band of the TWAP sqrt price around a plan's price.
     */
    function setDeviation(
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxSpotFromTrusted,
        uint256 newMaxTwapFromTrusted
    ) external onlyFactory {
        // Checks.
        if (newTwapWindow == 0) revert InvalidTwapWindow();

        // Update State.
        Config storage config = _state().config;
        config.twapWindow = newTwapWindow;
        config.maxSpotFromTwap = SafeCastLib.toUint64(newMaxSpotFromTwap);
        config.maxSpotFromTrusted = SafeCastLib.toUint64(newMaxSpotFromTrusted);
        config.maxTwapFromTrusted = SafeCastLib.toUint64(newMaxTwapFromTrusted);

        emit DeviationSet(newTwapWindow, newMaxSpotFromTwap, newMaxSpotFromTrusted, newMaxTwapFromTrusted);
    }

    /**
     * @notice Sets both protocol fees and their recipient.
     * @param newProtocolEmissionFeeBps The protocol share of claimed emissions.
     * @param newProtocolSwapFeeBps The protocol share of collected swap fees.
     * @param newFeeRecipient The recipient of the protocol fees.
     */
    function setProtocolFees(uint16 newProtocolEmissionFeeBps, uint16 newProtocolSwapFeeBps, address newFeeRecipient)
        external
        nonReentrant
        onlyFactory
    {
        // Checks.
        if (newProtocolEmissionFeeBps > ConfigLib.MAX_FEE_BPS || newProtocolSwapFeeBps > ConfigLib.MAX_FEE_BPS) {
            revert InvalidFee();
        }
        if (newFeeRecipient == address(0) || newFeeRecipient == address(this)) revert InvalidRecipient();

        // Collect the swap fees at the old fees.
        State storage state = _state();
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();
        (TokenDelta fees,,) = state.collectFees(POSITION_MANAGER, PoolLogic.sqrtPriceX96(immutables.pool));
        state.creditCollected(TokenDelta.wrap(0), fees);

        // Claim all emissions at the old fees, reverting when a penalty window hides some.
        if (state.claimGaugeEmissions(immutables.gauge, GAUGE_FACTORY)) revert RewardsPending();
        state.checkpoint(totalSupply(), REWARD_TOKEN, immutables.gauge, GAUGE_FACTORY, LEAF_VOTER);

        // Update State.
        Config storage config = state.config;
        config.protocolEmissionFeeBps = newProtocolEmissionFeeBps;
        config.protocolSwapFeeBps = newProtocolSwapFeeBps;
        config.feeRecipient = newFeeRecipient;

        emit ProtocolFeesSet(newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    /**
     * @notice Pays the protocol fees accrued on both pool tokens and on the reward token out.
     * @return amount0 The token0 paid.
     * @return amount1 The token1 paid.
     * @return amountReward The reward token paid.
     */
    function payProtocolFees()
        external
        nonReentrant
        onlyDelegated
        returns (uint256 amount0, uint256 amount1, uint256 amountReward)
    {
        // Cache the fee recipient and the core immutables.
        State storage state = _state();
        address recipient = state.config.feeRecipient;
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();

        // Transfer the protocol fees in pool tokens to the fee recipient.
        (amount0, amount1) =
            state.poolTokens.protocolFees.payProtocolFees(immutables.token0, immutables.token1, recipient);

        // Transfer the protocol fees in reward token to the fee recipient.
        amountReward = state.payProtocolFees(
            totalSupply(),
            REWARD_TOKEN,
            immutables.gauge,
            GAUGE_FACTORY,
            LEAF_VOTER,
            recipient,
            balanceOf(address(this))
        );

        emit ProtocolFeesPaid(amount0, amount1, amountReward);
    }

    /* //////////////////////////////////////////////////////////////
                                 REWARDS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Pays out the emissions credited to an account.
     * @param account The account whose reward is credited and paid.
     * @return amountReward The amount of reward token transferred.
     */
    function claimEmissions(address account) external nonReentrant onlyDelegated returns (uint256 amountReward) {
        // Transfer the emissions credited to the account to the account.
        amountReward = _state()
            .payReward(
                totalSupply(),
                REWARD_TOKEN,
                CalldataLogic.decodeCoreImmutables().gauge,
                GAUGE_FACTORY,
                LEAF_VOTER,
                account,
                balanceOf(account)
            );

        emit EmissionsClaimed(account, amountReward);
    }

    /**
     * @notice The emissions a holder is owed at this block, credited or not.
     * @param account The holder, not the core.
     * @return owed The reward token owed.
     */
    function getRewardOwed(address account) external view onlyDelegated returns (uint256 owed) {
        _requireUnlocked();

        // Calculate the reward per share a checkpoint at this block reaches.
        State storage state = _state();
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();
        (,, uint256 total) = state.getRewardTotals(REWARD_TOKEN, immutables.gauge);
        (uint128 rewardPerShare,,,) =
            state.getRewardPerShare(totalSupply(), total, immutables.gauge, GAUGE_FACTORY, LEAF_VOTER);

        // Add the reward credited so far and the reward the holder's balance earned since.
        RewardAccount storage rewardAccount = state.rewards.rewardAccounts[account];
        // Unchecked: rewardPerShare can underflow, what matters is the delta in rewardPerShare between two interactions.
        unchecked {
            owed = rewardAccount.rewardOwed
                + balanceOf(account).fullMulDiv(rewardPerShare - rewardAccount.rewardPerSharePaid, 1e18);
        }
    }

    /* //////////////////////////////////////////////////////////////
                                 VAULTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets whether an operator may act for a controller.
     * @param controller The account the operator acts for.
     * @param operator The account approved to act on the controller's behalf.
     * @param approved True to approve, false to revoke.
     * @return success True.
     */
    function setOperator(address controller, address operator, bool approved)
        external
        onlyDelegated
        returns (bool success)
    {
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();
        if (
            msg.sender != immutables.syncVault0 && msg.sender != immutables.syncVault1
                && msg.sender != immutables.asyncVault0 && msg.sender != immutables.asyncVault1
        ) {
            revert OnlyVault();
        }
        _state().share.isOperator[controller][operator] = approved;
        success = true;
    }

    /* //////////////////////////////////////////////////////////////
                           SYNCHRONOUS VAULT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Bootstraps the vault, once, before any mint.
     * @param amount0 The token0 amount pulled into the buffer.
     * @param amount1 The token1 amount pulled into the buffer.
     * @param shares The aLP supply minted, of which DEAD_SHARES go to address(1).
     * @param receiver The account the rest of the supply is minted to.
     */
    function seed(uint256 amount0, uint256 amount1, uint256 shares, address receiver)
        external
        nonReentrant
        onlyFactory
    {
        // Checks.
        State storage state = _state();
        if (totalSupply() > 0) revert AlreadySeeded();
        if (receiver == address(0)) revert InvalidRecipient();
        state.config.checkConfigured();
        if (shares <= DEAD_SHARES) revert InvalidShares();
        state.checkTotalCap(shares);
        // Unchecked: the check above bounds DEAD_SHARES by shares.
        unchecked {
            state.checkPerUserCap(receiver, shares - DEAD_SHARES);
        }
        if (amount0 == 0 || amount1 == 0) revert InvalidAmounts();

        // Cache the core immutables and the seed's value in token1 at the pool price.
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();
        uint160 sqrtPriceX96 = PoolLogic.sqrtPriceX96(immutables.pool);
        uint256 value = amount1 + CLMath.convert(sqrtPriceX96, true, amount0, false);

        // Pull the seed from the factory.
        immutables.token0.safeTransferFrom(msg.sender, address(this), amount0);
        immutables.token1.safeTransferFrom(msg.sender, address(this), amount1);

        // Update State.
        state.poolTokens.buffer.applyDelta(TokenDeltaLib.fromAmounts(amount0, amount1));

        // Set the exchange rate requests are estimated at.
        state.share.setLastExchangeRate(sqrtPriceX96, shares, value);

        // Mint DEAD_SHARES to address(1).
        _mint(address(1), DEAD_SHARES);

        // Mint the rest of the shares to the receiver.
        // Unchecked: the check above bounds DEAD_SHARES by shares.
        unchecked {
            _mint(receiver, shares - DEAD_SHARES);
        }

        emit Seeded(receiver, shares, amount0, amount1);
    }

    /* //////////////////////////////////////////////////////////////
                                INVENTORY
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accrues the untracked pool tokens to the protocol.
     * @return amount0 The token0 skimmed.
     * @return amount1 The token1 skimmed.
     */
    function skim() external nonReentrant onlyDelegated returns (uint256 amount0, uint256 amount1) {
        CoreImmutables memory immutables = CalldataLogic.decodeCoreImmutables();
        State storage state = _state();
        (amount0, amount1) = state.skim(immutables.token0, immutables.token1);

        emit Skimmed(amount0, amount1);
    }
}
