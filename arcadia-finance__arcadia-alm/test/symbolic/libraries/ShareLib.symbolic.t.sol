/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Config, ExchangeRate, ShareAccount } from "../../../src/core/types/State.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";
import { ShareLibExtension } from "../../utils/extensions/ShareLibExtension.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the library "ShareLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ShareLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ShareLibExtension internal shareLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        shareLib = new ShareLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_checkPerUserCap_SucceedsIffTheSumIsWithinTheCap(
        address account,
        uint128 balance,
        ShareAccount memory shareAccount,
        uint128 perUserCap
    ) public {
        // Given: A non-exempt account, any uint128 balance and record, and any cap.
        vm.assume(account != address(shareLib));
        Config memory config;
        config.perUserCap = perUserCap;
        shareLib.setConfig(config);
        shareLib.setShareAccount(account, shareAccount);
        shareLib.setCapExempt(account, false);
        uint256 sum = uint256(balance) + shareAccount.claimableShares + shareAccount.pendingShares;

        // When: Checking the per user cap.
        (bool success, bytes memory result) =
            address(shareLib).staticcall(abi.encodeCall(ShareLibExtension.checkPerUserCap, (account, balance)));

        // Then: It succeeds exactly when the unwrapped sum is within the cap.
        assertEq(success, sum <= perUserCap);
        if (!success) assertEq(result, abi.encodeWithSelector(ShareLib.PerUserCapExceeded.selector));
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_setLastExchangeRate_StoresTheSupplyPerValueRoundedUp(
        uint256 lastSqrtPriceX96,
        uint256 supply,
        uint256 value
    ) public {
        // Given: Any uint160 price, a uint128 supply and a nonzero value.
        vm.assume(lastSqrtPriceX96 <= type(uint160).max && supply <= type(uint128).max && value != 0);
        uint256 rateFloored = (supply << 128) / value;

        // When: Storing the exchange rate.
        shareLib.setLastExchangeRate(uint160(lastSqrtPriceX96), supply, value);

        // Then: It stores supply * 2^128 / value rounded up, and the price.
        ExchangeRate memory rate = shareLib.getLastExchangeRate();
        unchecked {
            assertEq(rate.supplyPerValueX128, rateFloored + (mulmod(supply, 1 << 128, value) == 0 ? 0 : 1));
        }
        assertEq(rate.sqrtPriceX96, lastSqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver = "cvc5-int"
    function prove_getPendingShares_Token1AtOrAboveTheLastPriceIsTheAssetsAtTheRateRoundedUp(
        uint256 assets,
        uint256 sqrtPriceX96,
        uint256 lastSqrtPriceX96,
        uint256 supplyPerValueX128
    ) public {
        // Given: uint128 assets and rate, and a last price at or below the price.
        vm.assume(lastSqrtPriceX96 != 0 && lastSqrtPriceX96 <= sqrtPriceX96 && sqrtPriceX96 <= type(uint160).max);
        vm.assume(assets <= type(uint128).max && supplyPerValueX128 <= type(uint128).max);
        shareLib.setLastExchangeRate(ExchangeRate(supplyPerValueX128, uint160(lastSqrtPriceX96)));
        uint256 sharesFloored = assets * supplyPerValueX128 >> 128;

        // When: Taking the pending shares of a token1 deposit.
        uint256 shares = shareLib.getPendingShares(false, assets, uint160(sqrtPriceX96));

        // Then: It is assets * rate / 2^128, rounded up.
        unchecked {
            assertEq(shares, sharesFloored + (mulmod(assets, supplyPerValueX128, 1 << 128) == 0 ? 0 : 1));
        }
    }
}
