/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Config, ExchangeRate, ShareAccount, State } from "../../../src/core/types/State.sol";

contract ShareLibExtension {
    State internal state;

    function setConfig(Config memory config) external {
        state.config = config;
    }

    function setCapExempt(address account, bool exempt) external {
        state.share.isExempt[account] = exempt;
    }

    function setShareAccount(address account, ShareAccount memory shareAccount) external {
        state.share.shareAccounts[account] = shareAccount;
    }

    function getShareAccount(address account) external view returns (ShareAccount memory shareAccount) {
        shareAccount = state.share.shareAccounts[account];
    }

    function checkTotalCap(uint256 supply) external view {
        state.checkTotalCap(supply);
    }

    function checkPerUserCap(address account, uint256 balance) external view {
        state.checkPerUserCap(account, balance);
    }

    function isCapExempt(address account) external view returns (bool exempt) {
        exempt = state.isCapExempt(account);
    }

    function setLastExchangeRate(uint160 lastSqrtPriceX96, uint256 supply, uint256 value) external {
        state.share.setLastExchangeRate(lastSqrtPriceX96, supply, value);
    }

    function setLastExchangeRate(ExchangeRate memory lastExchangeRate) external {
        state.share.lastExchangeRate = lastExchangeRate;
    }

    function getLastExchangeRate() external view returns (ExchangeRate memory lastExchangeRate) {
        lastExchangeRate = state.share.lastExchangeRate;
    }

    function getPendingShares(bool isToken0, uint256 assets, uint160 sqrtPriceX96)
        external
        view
        returns (uint256 shares)
    {
        shares = state.share.getPendingShares(isToken0, assets, sqrtPriceX96);
    }
}
