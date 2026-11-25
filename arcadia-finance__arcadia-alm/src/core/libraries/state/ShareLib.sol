/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ExchangeRate, Share, ShareAccount, State } from "../../types/State.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @title Share Library.
 * @author Pragma Labs
 * @notice The aLP ledger's caps, balances and exchange rate.
 */
// forge-lint: disable-next-item(require-revert-in-loop)
library ShareLib {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error LastExchangeRateNotSet();
    error PerUserCapExceeded();
    error TotalCapExceeded();

    /* //////////////////////////////////////////////////////////////
                                  CAPS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Reverts when an aLP supply would pass the total cap.
     * @param state The core state.
     * @param supply The aLP supply after the mint.
     */
    function checkTotalCap(State storage state, uint256 supply) internal view {
        // Checks.
        if (supply > state.config.totalCap) revert TotalCapExceeded();
    }

    /**
     * @notice Reverts when an account's balance plus its claimable and pending aLP passes the per user cap.
     * @param state The core state.
     * @param account The account, skipped when it is the core or exempt.
     * @param shares The account's aLP balance.
     */
    function checkPerUserCap(State storage state, address account, uint256 shares) internal view {
        // If the account is the core or exempt, skip the per user cap.
        if (isCapExempt(state, account)) return;

        // Checks.
        ShareAccount storage shareAccount = state.share.shareAccounts[account];
        // Unchecked: every term is within the uint128 total cap.
        unchecked {
            if (shares + shareAccount.claimableShares + shareAccount.pendingShares > state.config.perUserCap) {
                revert PerUserCapExceeded();
            }
        }
    }

    /**
     * @notice Whether an account is outside the per user cap.
     * @param state The core state.
     * @param account The account.
     * @return True for the core or an exempt account.
     */
    function isCapExempt(State storage state, address account) internal view returns (bool) {
        return account == address(this) || state.share.isExempt[account];
    }

    /* //////////////////////////////////////////////////////////////
                              EXCHANGE RATE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Stores an execution's closing rate for the deposit requests that come after it.
     * @param share The share token state.
     * @param lastSqrtPriceX96 The execution's trusted price.
     * @param supply The aLP supply after the execution.
     * @param value The vault value after the execution.
     */
    function setLastExchangeRate(Share storage share, uint160 lastSqrtPriceX96, uint256 supply, uint256 value)
        internal
    {
        // Update State.
        ExchangeRate storage lastExchangeRate = share.lastExchangeRate;
        lastExchangeRate.supplyPerValueX128 = supply.fullMulDivUp(1 << 128, value);
        lastExchangeRate.sqrtPriceX96 = lastSqrtPriceX96;
    }

    /**
     * @notice The pending aLP of a deposit of assets, at the last exchange rate, rounded up.
     * @param share The share token state.
     * @param isToken0 True when the asset is token0.
     * @param assets The asset amount.
     * @param sqrtPriceX96 The price the asset is valued at.
     * @return shares The aLP shares.
     */
    function getPendingShares(Share storage share, bool isToken0, uint256 assets, uint160 sqrtPriceX96)
        internal
        view
        returns (uint256 shares)
    {
        // Checks.
        ExchangeRate storage lastExchangeRate = share.lastExchangeRate;
        uint160 lastSqrtPriceX96 = lastExchangeRate.sqrtPriceX96;
        if (lastSqrtPriceX96 == 0) revert LastExchangeRateNotSet();

        // Calculate the value of the assets (the larger of the values at the current and the last price).
        uint256 value;
        if (isToken0) {
            uint256 upperSqrtPriceX96 = FixedPointMathLib.max(sqrtPriceX96, lastSqrtPriceX96);
            value = assets.fullMulDivUp(upperSqrtPriceX96, 1 << 96).fullMulDivUp(upperSqrtPriceX96, 1 << 96);
        } else {
            value = sqrtPriceX96 >= lastSqrtPriceX96
                ? assets
                : assets.fullMulDivUp(lastSqrtPriceX96, sqrtPriceX96).fullMulDivUp(lastSqrtPriceX96, sqrtPriceX96);
        }

        // Calculate the pending shares (at the last exchange rate).
        shares = value.fullMulDivUp(lastExchangeRate.supplyPerValueX128, 1 << 128);
    }
}
