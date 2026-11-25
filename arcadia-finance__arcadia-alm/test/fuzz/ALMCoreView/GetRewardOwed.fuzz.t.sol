/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @notice Fuzz tests for the function "getRewardOwed" of contract "ALMCoreView".
 */
contract GetRewardOwed_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
        deployCoreView();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getRewardOwed_CoreNotValid(address notCore, address account) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRewardOwed(notCore, account);
    }

    function testFuzz_Revert_getRewardOwed_CoreNotValid_HalfCreated(address account) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRewardOwed(core, account);
    }

    function testFuzz_Success_getRewardOwed_IsTheHoldersShareOfTheReward(
        uint256 shares,
        uint96 received,
        uint256 seedShares
    ) public {
        // Given: A supply seed keeping a uint96 reward per share a uint128.
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(deadAddress, seedShares);

        // And: A holder next to it, with reward token arrived.
        shares = bound(shares, 1, type(uint96).max);
        almCore.mintShares(accountA, shares);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        // When: Reading what the holder is owed through the lens.
        uint256 owed = coreView.getRewardOwed(address(almCore), accountA);

        // Then: It is the holder's part of the reward net of the protocol share.
        uint256 net = uint256(received)
            - uint256(received).fullMulDiv(almCore.protocolEmissionFeeBps_(), ConfigLib.BPS_DENOMINATOR);
        assertEq(owed, shares.fullMulDiv(net.fullMulDiv(1e18, seedShares + shares), 1e18));
    }

    function testFuzz_Success_getRewardOwed_AddsTheStepAcrossTheWrap(
        uint64 shares,
        uint64 seedShares,
        uint64 headroom,
        uint128 rewardOwed,
        uint128 received
    ) public {
        // Given: No emission fee and a holder next to a supply seed.
        seedShares = uint64(bound(seedShares, almCore.DEAD_SHARES_(), type(uint64).max));
        shares = uint64(bound(shares, 1, type(uint64).max));
        almCore.mintShares(deadAddress, seedShares);
        almCore.mintShares(accountA, shares);
        uint256 supply = almCore.totalSupply();

        // And: An accumulator near its width, the holder paid to it and owed a reward.
        headroom = uint64(bound(headroom, 0, type(uint64).max));
        uint256 accumulatorBefore = type(uint128).max - uint256(headroom);
        almCore.setRewardAccounting(accumulatorBefore, 0, 0, 0);
        almCore.setRewardSnapshot(accountA, accumulatorBefore);
        almCore.setPendingReward(accountA, rewardOwed);

        // And: A reward whose step per share passes the headroom and stays below 2^128.
        received = uint128(
            bound(
                received,
                (uint256(headroom) + 1).fullMulDivUp(supply, 1e18),
                FixedPointMathLib.min(uint256(type(uint128).max).fullMulDiv(supply, 1e18), type(uint128).max / 2)
            )
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);
        uint256 step = uint256(received).fullMulDiv(1e18, supply);

        // When: Reading what the holder is owed through the lens.
        uint256 owed = coreView.getRewardOwed(address(almCore), accountA);

        // Then: It is the reward owed plus the holder's share of the whole step.
        assertEq(owed, rewardOwed + uint256(shares).fullMulDiv(step, 1e18));
    }
}
