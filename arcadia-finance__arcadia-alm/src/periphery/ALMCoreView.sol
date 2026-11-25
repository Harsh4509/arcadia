/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../core/libraries/logic/ALMCoreViewLogic.sol";
import {
    Claimable,
    Config,
    Epoch,
    ExchangeRate,
    PoolTokens,
    Record,
    RewardAccount,
    ShareAccount
} from "../core/types/State.sol";
import { CLMath } from "../shared/libraries/math/CLMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../interfaces/IALMCore.sol";
import { IALMFactory } from "../interfaces/IALMFactory.sol";
import { PoolLogic } from "../shared/libraries/logic/PoolLogic.sol";
import { Position } from "./types/Position.sol";
import { Range } from "../core/types/Range.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Vaults } from "../core/types/Vaults.sol";

/**
 * @title ALM Core View.
 * @author Pragma Labs
 * @notice Read-only views of the cores of one factory.
 */
contract ALMCoreView {
    using ALMCoreViewLogic for IALMCore;
    using ALMCoreViewLogic for bytes32[];
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    // The factory whose cores this lens reads.
    address internal immutable FACTORY;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error CoreNotValid();
    error ZeroAddress();

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyCore(address core) {
        _requireCore(core);
        _;
    }

    /**
     * @notice Reverts unless the factory created a core.
     * @param core The core.
     */
    function _requireCore(address core) internal view {
        if (!IALMFactory(FACTORY).isCore(core)) revert CoreNotValid();
    }

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(address factory) {
        if (factory == address(0)) revert ZeroAddress();
        FACTORY = factory;
    }

    /* //////////////////////////////////////////////////////////////
                                 CONFIG
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice A core's governance parameters.
     * @param core The core.
     * @return config The governance parameters.
     */
    function getConfig(address core) external view onlyCore(core) returns (Config memory config) {
        config = IALMCore(core).getConfig();
    }

    /* //////////////////////////////////////////////////////////////
                                 REWARDS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice A core's emissions accumulator.
     * @param core The core.
     * @return rewardPerShare The reward per share accrued.
     * @return highWater The lifetime reward the accumulator last reached, raised by folded pre-credits.
     * @return claimedCumulative The reward token claimed in total.
     * @return lastRewardBalance The reward token balance at the last accrual.
     * @return protocolFees The reward token owed to the protocol.
     * @return protocolRewardPerSharePaid The reward per share the protocol's fee was paid at.
     * @return preCredited The emissions credited to holders that a penalty window still hides.
     */
    function getRewards(address core)
        external
        view
        onlyCore(core)
        returns (
            uint128 rewardPerShare,
            uint128 highWater,
            uint128 claimedCumulative,
            uint128 lastRewardBalance,
            uint128 protocolFees,
            uint128 protocolRewardPerSharePaid,
            uint128 preCredited
        )
    {
        return IALMCore(core).getRewards();
    }

    /**
     * @notice One holder's emissions position on a core.
     * @param core The core.
     * @param account The holder.
     * @return rewardAccount The reward per share paid and the reward owed.
     */
    function getRewardAccount(address core, address account)
        external
        view
        onlyCore(core)
        returns (RewardAccount memory rewardAccount)
    {
        rewardAccount = IALMCore(core).getRewardAccount(account);
    }

    /**
     * @notice The emissions a holder is owed on a core at this block, credited or not.
     * @param core The core.
     * @param account The holder.
     * @return owed The reward token owed.
     */
    function getRewardOwed(address core, address account) external view onlyCore(core) returns (uint256 owed) {
        owed = IALMCore(core).getRewardOwed(account);
    }

    /* //////////////////////////////////////////////////////////////
                                  SHARE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The exchange rate a core's last execution stored.
     * @param core The core.
     * @return lastExchangeRate The supply per unit of value and the price it was taken at.
     */
    function getLastExchangeRate(address core)
        external
        view
        onlyCore(core)
        returns (ExchangeRate memory lastExchangeRate)
    {
        lastExchangeRate = IALMCore(core).getLastExchangeRate();
    }

    /**
     * @notice One account's claimable and pending aLP on a core.
     * @param core The core.
     * @param account The account.
     * @return shareAccount The claimable and the pending aLP.
     */
    function getShareAccount(address core, address account)
        external
        view
        onlyCore(core)
        returns (ShareAccount memory shareAccount)
    {
        shareAccount = IALMCore(core).getShareAccount(account);
    }

    /**
     * @notice Whether an operator may act for a controller on a core.
     * @param core The core.
     * @param controller The account the operator acts for.
     * @param operator The operator.
     * @return approved True when approved.
     */
    function isOperator(address core, address controller, address operator)
        external
        view
        onlyCore(core)
        returns (bool approved)
    {
        approved = IALMCore(core).isOperator(controller, operator);
    }

    /**
     * @notice Whether governance exempted an account from a core's per user cap.
     * @param core The core.
     * @param account The account.
     * @return exempt True when exempted.
     */
    function isExempt(address core, address account) external view onlyCore(core) returns (bool exempt) {
        exempt = IALMCore(core).isExempt(account);
    }

    /* //////////////////////////////////////////////////////////////
                               POOL TOKENS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice A core's buffer, the pool tokens it owes the protocol and the escrow of the requests.
     * @param core The core.
     * @return poolTokens The buffer, the fees owed and the escrow.
     */
    function getPoolTokens(address core) external view onlyCore(core) returns (PoolTokens memory poolTokens) {
        poolTokens = IALMCore(core).getPoolTokens();
    }

    /* //////////////////////////////////////////////////////////////
                                 RANGES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Every range of a core.
     * @param core The core.
     * @return ranges The ranges.
     */
    function getRanges(address core) external view onlyCore(core) returns (Range[] memory ranges) {
        ranges = IALMCore(core).readRangeWords().decodeRanges();
    }

    /* //////////////////////////////////////////////////////////////
                                 QUEUES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice A vault's pending deposit epoch on a core.
     * @param core The core.
     * @param vault The vault.
     * @return pendingEpoch The id of the pending deposit epoch.
     */
    function getPendingDepositEpoch(address core, address vault)
        external
        view
        onlyCore(core)
        returns (uint32 pendingEpoch)
    {
        pendingEpoch = IALMCore(core).getPendingDepositEpoch(vault);
    }

    /**
     * @notice A vault's pending redeem epoch on a core.
     * @param core The core.
     * @param vault The vault.
     * @return pendingEpoch The id of the pending redeem epoch.
     */
    function getPendingRedeemEpoch(address core, address vault)
        external
        view
        onlyCore(core)
        returns (uint32 pendingEpoch)
    {
        pendingEpoch = IALMCore(core).getPendingRedeemEpoch(vault);
    }

    /**
     * @notice A vault's last cleared deposit epoch on a core.
     * @param core The core.
     * @param vault The vault.
     * @return lastClearedEpoch The id of the deposit epoch the last clear moved requests into.
     */
    function getLastClearedDepositEpoch(address core, address vault)
        external
        view
        onlyCore(core)
        returns (uint32 lastClearedEpoch)
    {
        lastClearedEpoch = IALMCore(core).getLastClearedDepositEpoch(vault);
    }

    /**
     * @notice A vault's last cleared redeem epoch on a core.
     * @param core The core.
     * @param vault The vault.
     * @return lastClearedEpoch The id of the redeem epoch the last clear moved requests into.
     */
    function getLastClearedRedeemEpoch(address core, address vault)
        external
        view
        onlyCore(core)
        returns (uint32 lastClearedEpoch)
    {
        lastClearedEpoch = IALMCore(core).getLastClearedRedeemEpoch(vault);
    }

    /**
     * @notice A vault's deposit epoch on a core.
     * @param core The core.
     * @param vault The vault.
     * @param epoch The epoch id.
     * @return epoch_ The input and the output.
     */
    function getDepositEpoch(address core, address vault, uint32 epoch)
        external
        view
        onlyCore(core)
        returns (Epoch memory epoch_)
    {
        epoch_ = IALMCore(core).getDepositEpoch(vault, epoch);
    }

    /**
     * @notice A vault's redeem epoch on a core.
     * @param core The core.
     * @param vault The vault.
     * @param epoch The epoch id.
     * @return epoch_ The input and the output.
     */
    function getRedeemEpoch(address core, address vault, uint32 epoch)
        external
        view
        onlyCore(core)
        returns (Epoch memory epoch_)
    {
        epoch_ = IALMCore(core).getRedeemEpoch(vault, epoch);
    }

    /**
     * @notice A controller's deposit record on a vault of a core.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return record The epoch, the amount in and the pending aLP.
     */
    function getDepositRecord(address core, address vault, address controller)
        external
        view
        onlyCore(core)
        returns (Record memory record)
    {
        record = IALMCore(core).getDepositRecord(vault, controller);
    }

    /**
     * @notice A controller's redeem record on a vault of a core.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return record The epoch, the amount in and the pending aLP.
     */
    function getRedeemRecord(address core, address vault, address controller)
        external
        view
        onlyCore(core)
        returns (Record memory record)
    {
        record = IALMCore(core).getRedeemRecord(vault, controller);
    }

    /**
     * @notice A controller's pending deposit assets on a vault of a core.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return assets The asset amount, zero unless the record is pending.
     */
    function getPendingDeposit(address core, address vault, address controller)
        external
        view
        onlyCore(core)
        returns (uint256 assets)
    {
        assets = IALMCore(core).getPendingDeposit(vault, controller);
    }

    /**
     * @notice A controller's pending redeem aLP on a vault of a core.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return shares The aLP, zero unless the record is pending.
     */
    function getPendingRedeem(address core, address vault, address controller)
        external
        view
        onlyCore(core)
        returns (uint256 shares)
    {
        shares = IALMCore(core).getPendingRedeem(vault, controller);
    }

    /**
     * @notice A controller's claimable deposits on a vault of a core, including a settled record.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return claimable The settled input and output.
     */
    function getClaimableDeposit(address core, address vault, address controller)
        external
        view
        onlyCore(core)
        returns (Claimable memory claimable)
    {
        (claimable.amountIn, claimable.amountOut) = IALMCore(core).getClaimableDeposit(vault, controller);
    }

    /**
     * @notice A controller's claimable redeems on a vault of a core, including a settled record.
     * @param core The core.
     * @param vault The vault.
     * @param controller The controller.
     * @return claimable The settled input and output.
     */
    function getClaimableRedeem(address core, address vault, address controller)
        external
        view
        onlyCore(core)
        returns (Claimable memory claimable)
    {
        (claimable.amountOut, claimable.amountIn) = IALMCore(core).getClaimableRedeem(vault, controller);
    }

    /* //////////////////////////////////////////////////////////////
                                  LOCK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether a core's reentrancy lock is set.
     * @param core The core.
     * @return locked True while the lock is set.
     */
    function isLocked(address core) external view onlyCore(core) returns (bool locked) {
        locked = IALMCore(core).isLocked();
    }

    /* //////////////////////////////////////////////////////////////
                                POSITION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice An account's aLP on a core, its escrowed requests included, as one LpSugar position.
     * @param core The core.
     * @param account The account.
     * @return position The account's share of the ranges, the buffer and the fees, its escrowed assets and emissions.
     * @dev The ticks span every range, a core with several ranges has no single tick range.
     */
    function getPosition(address core, address account)
        external
        view
        onlyCore(core)
        returns (Position memory position)
    {
        position.id = uint256(uint160(core));
        position.lp = IALMFactory(FACTORY).poolOf(core);
        position.emissionsEarned = IALMCore(core).getRewardOwed(account);

        // Add the aLP and the assets the account holds in escrow in both vaults' queues.
        uint256 shares = IALMCore(core).balanceOf(account);
        {
            Vaults memory vaults = IALMFactory(FACTORY).getVaults(core);
            uint256 escrowedShares;
            (escrowedShares, position.amount0) = _getEscrowed(IALMCore(core), vaults.asyncVault0, account);
            shares += escrowedShares;
            (escrowedShares, position.amount1) = _getEscrowed(IALMCore(core), vaults.asyncVault1, account);
            shares += escrowedShares;
        }
        if (shares == 0) return position;

        // Add the account's share of the uncollected fees as its earned fees.
        uint256 supply = IALMCore(core).totalSupply();
        uint128[] memory positionLiquidity;
        (position.unstakedEarned0, position.unstakedEarned1, positionLiquidity) = IALMCore(core).getUnstakedPositions();
        position.unstakedEarned0 = position.unstakedEarned0.fullMulDiv(shares, supply);
        position.unstakedEarned1 = position.unstakedEarned1.fullMulDiv(shares, supply);

        // Add the account's share of the unstaked and the staked side of every range at spot.
        uint160 sqrtPriceX96 = PoolLogic.sqrtPriceX96(position.lp);
        Range[] memory ranges = IALMCore(core).readRangeWords().decodeRanges();
        uint160 sqrtPriceLowerX96;
        uint160 sqrtPriceUpperX96;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        for (uint256 i; i < ranges.length; ++i) {
            (sqrtPriceLowerX96, sqrtPriceUpperX96) =
            (TickMath.getSqrtPriceAtTick(ranges[i].tickLower), TickMath.getSqrtPriceAtTick(ranges[i].tickUpper));

            liquidity = SafeCastLib.toUint128(uint256(positionLiquidity[i]).fullMulDiv(shares, supply));
            (amount0, amount1) =
                CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, liquidity);
            position.liquidity += liquidity;
            position.amount0 += amount0;
            position.amount1 += amount1;

            liquidity = SafeCastLib.toUint128(uint256(ranges[i].stakedLiquidity).fullMulDiv(shares, supply));
            (amount0, amount1) =
                CLMath.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, liquidity);
            position.staked += liquidity;
            position.staked0 += amount0;
            position.staked1 += amount1;

            if (i == 0 || ranges[i].tickLower < position.tickLower) {
                (position.tickLower, position.sqrtRatioLower) = (ranges[i].tickLower, sqrtPriceLowerX96);
            }
            if (i == 0 || ranges[i].tickUpper > position.tickUpper) {
                (position.tickUpper, position.sqrtRatioUpper) = (ranges[i].tickUpper, sqrtPriceUpperX96);
            }
        }

        // Add the account's share of the buffer.
        (amount0, amount1) = IALMCore(core).getBuffer();
        position.amount0 += amount0.fullMulDiv(shares, supply);
        position.amount1 += amount1.fullMulDiv(shares, supply);
    }

    /**
     * @notice The aLP and the assets an account holds in escrow in one vault's queues.
     * @param core The core.
     * @param vault The asynchronous vault.
     * @param account The account, as the requests' controller.
     * @return shares The pending redeem aLP and the claimable deposit aLP.
     * @return assets The pending deposit assets and the claimable redeem assets, in the vault's asset.
     */
    function _getEscrowed(IALMCore core, address vault, address account)
        internal
        view
        returns (uint256 shares, uint256 assets)
    {
        (, uint256 depositShares) = core.getClaimableDeposit(vault, account);
        (uint256 redeemAssets,) = core.getClaimableRedeem(vault, account);
        shares = core.getPendingRedeem(vault, account) + depositShares;
        assets = core.getPendingDeposit(vault, account) + redeemAssets;
    }
}
