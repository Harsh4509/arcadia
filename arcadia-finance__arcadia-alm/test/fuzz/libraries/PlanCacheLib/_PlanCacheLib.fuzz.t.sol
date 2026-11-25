/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Fuzz_Test } from "../../Fuzz.t.sol";
import { MetadexCLFixture } from "../../../utils/fixtures/metadex/MetadexCLFixture.f.sol";
import { PlanCache } from "../../../../src/core/types/PlanCache.sol";
import { PlanCacheLibExtension } from "../../../utils/extensions/PlanCacheLibExtension.sol";
import { toTokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Common logic needed by all "PlanCacheLib" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract PlanCacheLib_Fuzz_Test is Fuzz_Test, MetadexCLFixture {
    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    struct SettlementState {
        uint160 sqrtPrice;
        uint256 supply;
        uint256 held0;
        uint256 held1;
        uint256 deposit0;
        uint256 deposit1;
        uint256 redeem0;
        uint256 redeem1;
        int256 swap0;
        int256 swap1;
        int256 other0;
        int256 other1;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    PlanCacheLibExtension internal planCacheLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        planCacheLib = new PlanCacheLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                            SETTLEMENT STATE
    ////////////////////////////////////////////////////////////// */

    function setSettlementState(SettlementState memory state) internal view returns (PlanCache memory cache) {
        cache = planCacheLib.start(state.sqrtPrice, state.sqrtPrice, state.supply, state.held0, state.held1);
        (cache.depositAssets0, cache.depositAssets1) = (state.deposit0, state.deposit1);
        (cache.redeemShares0, cache.redeemShares1) = (state.redeem0, state.redeem1);
        cache.swapDelta = toTokenDelta(int128(state.swap0), int128(state.swap1));
        cache.amount0 = int256(state.held0 + state.deposit0) + state.swap0 + state.other0;
        cache.amount1 = int256(state.held1 + state.deposit1) + state.swap1 + state.other1;
    }
}
