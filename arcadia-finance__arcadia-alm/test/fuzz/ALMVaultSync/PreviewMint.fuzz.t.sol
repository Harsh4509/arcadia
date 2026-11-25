/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";

/**
 * @notice Fuzz tests for the function "previewMint" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract PreviewMint_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_previewMint_CoreNotDeployed(PoolState memory poolState, bool isToken0, uint256 shares)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading previewMint() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultSync(vault).previewMint(shares);
    }

    function testFuzz_Revert_previewMint_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The core's lock is held.
        almCore.lock_();

        // When: Previewing a mint.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        vault.previewMint(shares);
    }

    function testFuzz_Revert_previewMint_NotInitialized(PoolState memory poolState, uint256 shares, bool isToken0)
        public
    {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Previewing a mint.
        // Then: It reverts, there being no supply to quote against.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        vault.previewMint(shares);
    }

    function testFuzz_Success_previewMint_NeverBelowTheValue(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A mint up to the supply buying at most half the depth, a hole if none.
        uint256 ceiling =
            FixedPointMathLib.min(almCore.totalSupply(), mintableWithinDepth(isToken0, poolState.liquidityPool));
        vm.assume(ceiling > 0);
        shares = bound(shares, 1, ceiling);

        // And: What the shares' part of the holdings is worth at spot, rounded down.
        uint256 least;
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            (uint256 value0, uint256 value1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                uint128(
                    (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
                    .fullMulDiv(shares, supply)
                )
            );
            value0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
            value1 += almCore.bufferAmount1().fullMulDiv(shares, supply);
            least = isToken0
                ? value0 + token1ToToken0(sqrtPriceX96(pool), value1)
                : value1 + token0ToToken1(sqrtPriceX96(pool), value0);
        }

        // When: Previewing a mint.
        uint256 quoted = vault.previewMint(shares);

        // Then: It quotes at least what the shares are worth.
        assertGe(quoted, least);
    }

    function testFuzz_Success_previewMint_NeverBelowTheCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: At most maxMint, a zero maxMint a hole no bound expresses.
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
            vm.assume(ceiling > 0);
            shares = bound(shares, 1, ceiling);
        }
        uint256 quoted = vault.previewMint(shares);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), quoted, address(vault));

        // When: The caller mints through the plain signature, bounded by that preview.
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(shares, users.unprivilegedAddress);

        // Then: The preview never quoted less than the mint cost.
        assertLe(assets, quoted);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(users.unprivilegedAddress), quoted - assets);
    }
}
