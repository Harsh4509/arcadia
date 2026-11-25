/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { MetadexCLFixture } from "../../utils/fixtures/metadex/MetadexCLFixture.f.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice Common logic needed by the library fuzz tests that stake a range in a Metadex CL gauge.
 */
abstract contract StakedRange_Fuzz_Test is MetadexCLFixture {
    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function stakeIntoRange(
        ICLPool clPool,
        ICLGauge clGauge,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (Range memory range) {
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(clPool), tickLower, tickUpper, liquidity);
        (uint256 tokenId, uint128 minted) = mintPosition(clPool, owner, tickLower, tickUpper, amount0, amount1);
        stake(clGauge, owner, tokenId);
        range = Range({
            stakedLiquidity: minted,
            tickLower: tickLower,
            tickUpper: tickUpper,
            unstakedTokenId: 0,
            stakedTokenId: SafeCastLib.toUint80(tokenId),
            stakedBlock: SafeCastLib.toUint48(clGauge.depositBlock(tokenId))
        });
    }
}
