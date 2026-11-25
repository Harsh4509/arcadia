/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IArbSys } from "../../../../src/interfaces/IArbSys.sol";
import { IMetadexCLGaugeFactory } from "../../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claimableTokenIds" of library "RangesLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ClaimableTokenIds_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(RangesLib_Fuzz_Test) {
        RangesLib_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_claimableTokenIds_NoRanges(PoolState memory poolState, uint256 blocksPassed) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: No ranges at all, at any block.
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, type(uint48).max - vm.getBlockNumber()));

        // When: Listing the claimable token ids.
        // Then: The list is empty.
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));
        assertEq(claimable.length, 0);
    }

    function testFuzz_Success_claimableTokenIds_SkipsARangeWithNoStakedSibling(
        PoolState memory poolState,
        uint256 blocksPassed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: An unstaked range, well past any penalty window.
        pushStaked(0, uint48(vm.getBlockNumber()));
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, type(uint48).max - vm.getBlockNumber()));

        // When: Listing the claimable token ids.
        // Then: It is left out.
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));
        assertEq(claimable.length, 0);
    }

    function testFuzz_Success_claimableTokenIds_SkipsARangeInsideItsPenaltyWindow(
        PoolState memory poolState,
        uint80 tokenId,
        uint256 blocksPassed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A staked range whose deposit is still inside the gauge's penalty window.
        pushStaked(uint80(bound(tokenId, 1, type(uint80).max)), uint48(vm.getBlockNumber()));
        uint256 minStakeBlocks = clGaugeFactory.minStakeBlocks(address(gauge));
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, minStakeBlocks - 1));

        // When: Listing the claimable token ids.
        // Then: It is left out, and reported as skipped.
        (uint256[] memory claimable, bool skipped) =
            rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));
        assertEq(claimable.length, 0);
        assertTrue(skipped);
    }

    function testFuzz_Success_claimableTokenIds_SkipsAnOpenWindowPastUint32Blocks(
        PoolState memory poolState,
        uint80 tokenId,
        uint256 startBlock,
        uint256 blocksPassed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A chain past 2^32 blocks, and a staked range inside its penalty window.
        uint256 minStakeBlocks = clGaugeFactory.minStakeBlocks(address(gauge));
        vm.roll(bound(startBlock, uint256(type(uint32).max) + 1, type(uint48).max - minStakeBlocks));
        pushStaked(uint80(bound(tokenId, 1, type(uint80).max)), uint48(vm.getBlockNumber()));
        vm.roll(vm.getBlockNumber() + bound(blocksPassed, 0, minStakeBlocks - 1));

        // When: Listing the claimable token ids.
        // Then: It is left out.
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));
        assertEq(claimable.length, 0);
    }

    function testFuzz_Success_claimableTokenIds_SkipsAWindowOpenAtTheArbBlock(
        PoolState memory poolState,
        uint80 tokenId,
        uint256 blocksPassed,
        uint256 stakedBlock,
        uint256 arbBlockNumber
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A chain whose gauges count blocks with ArbSys.arbBlockNumber.
        rangesLib.setArbBlockNumber(true);
        vm.etch(address(0x64), hex"00");

        // And: A staked range whose window closed at the block, open at the arb block.
        uint256 minStakeBlocks = clGaugeFactory.minStakeBlocks(address(gauge));
        vm.roll(vm.getBlockNumber() + minStakeBlocks + bound(blocksPassed, 0, type(uint32).max));
        stakedBlock = bound(stakedBlock, 0, vm.getBlockNumber() - minStakeBlocks);
        pushStaked(uint80(bound(tokenId, 1, type(uint80).max)), uint48(stakedBlock));
        arbBlockNumber = bound(arbBlockNumber, stakedBlock, stakedBlock + minStakeBlocks - 1);
        vm.mockCall(address(0x64), abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(arbBlockNumber));

        // When: Listing the claimable token ids.
        // Then: It is left out.
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));
        assertEq(claimable.length, 0);
    }

    function testFuzz_Success_claimableTokenIds_ListsAWindowClosedAtTheArbBlock(
        PoolState memory poolState,
        uint80 tokenId,
        uint256 arbBlockNumber
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A chain whose gauges count blocks with ArbSys.arbBlockNumber.
        rangesLib.setArbBlockNumber(true);
        vm.etch(address(0x64), hex"00");

        // And: A staked range whose window is open at the block, closed at the arb block.
        uint80 staked = uint80(bound(tokenId, 1, type(uint80).max));
        pushStaked(staked, uint48(vm.getBlockNumber()));
        arbBlockNumber = bound(
            arbBlockNumber, vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)), type(uint48).max
        );
        vm.mockCall(address(0x64), abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(arbBlockNumber));

        // When: Listing the claimable token ids.
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));

        // Then: It is the only entry.
        assertEq(claimable.length, 1);
        assertEq(claimable[0], staked);
    }

    function testFuzz_Success_claimableTokenIds_ListsARangeOutsideItsPenaltyWindow(
        PoolState memory poolState,
        uint80 tokenId
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A staked range whose penalty window has closed.
        uint80 staked = uint80(bound(tokenId, 1, type(uint80).max));
        pushStaked(staked, uint48(vm.getBlockNumber()));
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));

        // When: Listing the claimable token ids.
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));

        // Then: It is the only entry.
        assertEq(claimable.length, 1);
        assertEq(claimable[0], staked);
    }

    function testFuzz_Success_claimableTokenIds_ListsOnlyTheRangeOutsideItsPenaltyWindow(
        PoolState memory poolState,
        uint80 first,
        uint80 second
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A staked range whose penalty window has closed, and one staked since.
        first = uint80(bound(first, 1, type(uint80).max));
        second = uint80(bound(second, 1, type(uint80).max));
        pushStaked(first, uint48(vm.getBlockNumber()));
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
        pushStaked(second, uint48(vm.getBlockNumber()));

        // When: Listing the claimable token ids.
        vm.expectCall(
            address(clGaugeFactory),
            abi.encodeWithSelector(IMetadexCLGaugeFactory.effectivePenaltyConfig.selector, address(gauge)),
            1
        );
        (uint256[] memory claimable,) = rangesLib.claimableTokenIds(address(gauge), address(clGaugeFactory));

        // Then: Only the first is listed, the penalty configuration read once.
        assertEq(claimable.length, 1);
        assertEq(claimable[0], first);
    }
}
