/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "maxMint" of library "ALMCoreViewLogic".
 */
contract MaxMint_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_maxMint_TheSmallerRoom(
        uint96 balance,
        uint96 escrowed,
        uint96 pending,
        uint256 totalRoom,
        uint256 perUserCap
    ) public {
        // Given: An account's balance, escrow and pending.
        almCore.mintShares(accountA, balance);
        almCore.mintShares(address(almCore), escrowed);
        almCore.setClaimableShares(accountA, escrowed);
        almCore.setPendingShares(accountA, pending);

        // And: A total cap a fuzzed room above the supply, and a fuzzed per user cap.
        uint256 supply = almCore.totalSupply();
        totalRoom = bound(totalRoom, 0, type(uint128).max - supply);
        perUserCap = bound(perUserCap, 0, type(uint128).max);
        vm.startPrank(factory);
        almCore.setTotalCap(supply + totalRoom);
        almCore.setPerUserCap(perUserCap);
        vm.stopPrank();

        // When: Reading its headroom.
        uint256 room = coreViewLogic.maxMint(address(almCore), accountA);

        // Then: It is the smaller of the total cap room and the per user cap room.
        uint256 capBalance = uint256(balance) + escrowed + pending;
        uint256 userRoom = perUserCap > capBalance ? perUserCap - capBalance : 0;
        assertEq(room, totalRoom < userRoom ? totalRoom : userRoom);
    }

    function testFuzz_Success_maxMint_Exempt(uint96 pending, uint256 totalRoom) public {
        // Given: An exempt account with pending shares.
        almCore.setPendingShares(accountA, pending);
        uint256 totalCap = almCore.totalSupply() + bound(totalRoom, 0, type(uint128).max);
        vm.startPrank(factory);
        almCore.setCapExempt(accountA, true);
        almCore.setPerUserCap(0);
        almCore.setTotalCap(totalCap);
        vm.stopPrank();

        // When: Reading its headroom.
        uint256 room = coreViewLogic.maxMint(address(almCore), accountA);

        // Then: It is the total cap room only.
        assertEq(room, totalCap - almCore.totalSupply());
    }

    function testFuzz_Success_maxMint_ZeroWhenPaused(ConfigState memory configState, address account) public {
        // Given: Room under both caps, and a paused core.
        givenValidConfigState(configState);
        configState.paused = true;
        setConfigState(configState);

        // When: Reading any account's headroom.
        // Then: It is zero.
        assertEq(coreViewLogic.maxMint(address(almCore), account), 0);
    }

    function testFuzz_Success_maxMint_ZeroForTheCore(ConfigState memory configState) public {
        // Given: Room under both caps, and a core that is not paused.
        givenValidConfigState(configState);
        configState.paused = false;
        setConfigState(configState);

        // When: Reading the core's headroom.
        // Then: It is zero.
        assertEq(coreViewLogic.maxMint(address(almCore), address(almCore)), 0);
    }
}
