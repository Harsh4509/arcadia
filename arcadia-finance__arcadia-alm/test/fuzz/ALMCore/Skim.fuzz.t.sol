/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";

/**
 * @notice Fuzz tests for the function "skim" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
contract Skim_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_skim_AccruesDonationToProtocol(
        address caller,
        uint256 buffered0,
        uint256 buffered1,
        uint256 donated0,
        uint256 donated1
    ) public {
        // Given: A funded buffer and a donation on top of it.
        fundBuffer(bound(buffered0, 0, Constants.MAX_FUZZED_AMOUNT), bound(buffered1, 0, Constants.MAX_FUZZED_AMOUNT));
        uint256 before0 = almCore.bufferAmount0();
        uint256 before1 = almCore.bufferAmount1();
        donated0 = bound(donated0, 0, Constants.MAX_FUZZED_AMOUNT);
        donated1 = bound(donated1, 0, Constants.MAX_FUZZED_AMOUNT);
        ERC20Mock(address(token0)).mint(address(almCore), donated0);
        ERC20Mock(address(token1)).mint(address(almCore), donated1);

        // When: Anyone calls skim().
        vm.prank(caller);
        (uint256 amount0, uint256 amount1) = almCore.skim();

        // Then: The donation is exactly what was skimmed, and the protocol is owed it.
        assertEq(amount0, donated0);
        assertEq(amount1, donated1);
        assertEq(almCore.getProtocolFees0(), donated0);
        assertEq(almCore.getProtocolFees1(), donated1);

        // And: The buffer that backs the shares is untouched.
        assertEq(almCore.bufferAmount0(), before0);
        assertEq(almCore.bufferAmount1(), before1);
    }

    function testFuzz_Success_skim_LeavesEscrowUntouched(
        uint256 owed0,
        uint256 owed1,
        uint256 escrowed0,
        uint256 escrowed1,
        uint256 donated0,
        uint256 donated1
    ) public {
        // Given: Fees owed and assets in escrow, both backed by real balances.
        owed0 = bound(owed0, 0, Constants.MAX_FUZZED_AMOUNT);
        owed1 = bound(owed1, 0, Constants.MAX_FUZZED_AMOUNT);
        escrowed0 = bound(escrowed0, 0, Constants.MAX_FUZZED_AMOUNT);
        escrowed1 = bound(escrowed1, 0, Constants.MAX_FUZZED_AMOUNT);
        ERC20Mock(address(token0)).mint(address(almCore), owed0 + escrowed0);
        ERC20Mock(address(token1)).mint(address(almCore), owed1 + escrowed1);
        almCore.setFeesOwed(owed0, owed1, 0);
        almCore.setEscrowed(escrowed0, escrowed1);

        // And: A donation on top of them, within the room the fees owed leave.
        donated0 = bound(donated0, 0, Constants.MAX_FUZZED_AMOUNT - owed0);
        donated1 = bound(donated1, 0, Constants.MAX_FUZZED_AMOUNT - owed1);
        ERC20Mock(address(token0)).mint(address(almCore), donated0);
        ERC20Mock(address(token1)).mint(address(almCore), donated1);

        // When: Calling skim().
        (uint256 amount0, uint256 amount1) = almCore.skim();

        // Then: Only the donation moved, added to what the protocol was already owed.
        assertEq(amount0, donated0);
        assertEq(amount1, donated1);
        assertEq(almCore.getProtocolFees0(), owed0 + donated0);
        assertEq(almCore.getProtocolFees1(), owed1 + donated1);

        // And: The escrow is still backed and the buffer is still empty.
        assertEq(almCore.getEscrowed0(), escrowed0);
        assertEq(almCore.getEscrowed1(), escrowed1);
        assertEq(almCore.bufferAmount0(), 0);
        assertEq(almCore.bufferAmount1(), 0);
    }

    function testFuzz_Success_skim_NothingToSkim(uint256 buffered0, uint256 buffered1) public {
        // Given: A buffer that already accounts for every token held.
        fundBuffer(bound(buffered0, 0, Constants.MAX_FUZZED_AMOUNT), bound(buffered1, 0, Constants.MAX_FUZZED_AMOUNT));
        uint256 before0 = almCore.bufferAmount0();
        uint256 before1 = almCore.bufferAmount1();

        // When: Calling skim().
        (uint256 amount0, uint256 amount1) = almCore.skim();

        // Then: Nothing moves.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(almCore.bufferAmount0(), before0);
        assertEq(almCore.bufferAmount1(), before1);
    }

    function testFuzz_Success_skim_EmitsSkimmed(uint256 donated0, uint256 donated1) public {
        // Given: A donation.
        donated0 = bound(donated0, 0, Constants.MAX_FUZZED_AMOUNT);
        donated1 = bound(donated1, 0, Constants.MAX_FUZZED_AMOUNT);
        ERC20Mock(address(token0)).mint(address(almCore), donated0);
        ERC20Mock(address(token1)).mint(address(almCore), donated1);

        // When: Calling skim().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Skimmed(donated0, donated1);
        // Then: It emits Skimmed.
        almCore.skim();
    }

    function testFuzz_Success_skim_LeavesTheEtherOnTheCore(uint256 stray) public {
        // Given: Ether on the core.
        stray = bound(stray, 1, type(uint128).max);
        vm.deal(address(almCore), stray);
        uint256 balance = users.feeRecipient.balance;

        // When: Anyone calls skim().
        almCore.skim();

        // Then: The ether stays on the core.
        assertEq(address(almCore).balance, stray);
        assertEq(users.feeRecipient.balance, balance);
    }
}
