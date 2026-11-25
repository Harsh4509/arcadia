/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { Constants } from "../../../utils/Constants.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { IALMCore } from "../../../../src/interfaces/IALMCore.sol";
import { Range_Fuzz_Test } from "../_Range.fuzz.t.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../../utils/extensions/SnapshotLibExtension.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "SnapshotLib" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract SnapshotLib_Fuzz_Test is ALMCore_Fuzz_Test, Range_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    struct SnapshotState {
        uint160 sqrtPriceX96;
        uint128 supply;
        uint64 idle0;
        uint64 idle1;
        uint64 fees0;
        uint64 fees1;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test, Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        snapshotLib = new SnapshotLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidSnapshot(SnapshotState memory state, RangeState memory range)
        internal
        pure
        returns (Snapshot memory snapshot)
    {
        // And: A spot price in the band, a supply, buffers, and a range around spot.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 1)
            )
        );
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        int24 tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK, tick));
        range.tickUpper = int24(bound(range.tickUpper, tick + 1, Constants.BOUND_TICK));
        range.liquidity = uint128(bound(range.liquidity, 1, type(uint64).max));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, type(uint64).max));

        RangeState[] memory ranges = new RangeState[](1);
        ranges[0] = range;
        snapshot = Snapshot({
            buffer0: state.idle0,
            buffer1: state.idle1,
            fees0: state.fees0,
            fees1: state.fees1,
            supply: state.supply,
            sqrtPriceX96: state.sqrtPriceX96,
            tick: tick,
            fee: 0,
            core: IALMCore(address(0)),
            ranges: pricedOf(ranges)
        });
    }

    function mintCost(
        RangeState[] memory ranges,
        uint160 sqrtPriceX96,
        uint256 idle0,
        uint256 idle1,
        uint256 shares,
        uint256 supply,
        bool zeroForOne,
        bool isToken0
    ) internal view returns (uint256 cost) {
        try snapshotLib.getMintAmounts(
            pricedOf(ranges), sqrtPriceX96, idle0, idle1, shares, supply, zeroForOne
        ) returns (
            uint256 cost0, uint256 cost1
        ) {
            cost = isToken0 ? cost0 : cost1;
        } catch {
            cost = type(uint256).max;
        }
    }
}
