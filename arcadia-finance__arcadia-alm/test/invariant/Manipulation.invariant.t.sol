/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../utils/Constants.sol";
import { Invariant_Test } from "./Invariant.t.sol";
import { ISwapRouter } from "../utils/fixtures/metadex/interfaces/ISwapRouter.sol";
import { ManipulatorHandler } from "./handlers/ManipulatorHandler.sol";
import { Vaults } from "../../src/core/types/Vaults.sol";

/**
 * @notice Invariant tests for a price round trip around "ALMCore".
 */
contract Manipulation_Invariant_Test is Invariant_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ManipulatorHandler internal manipulator;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(Invariant_Test) {
        Invariant_Test.setUp();
        setInvariantState();
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        Vaults memory vaults = deployer.getVaults(address(almCore));
        manipulator = new ManipulatorHandler(
            almCore, ISwapRouter(address(SWAP_ROUTER)), makeAddr("manipulator"), vaults.syncVault0, vaults.syncVault1
        );

        targetContract(address(manipulator));
    }

    /* //////////////////////////////////////////////////////////////
                                 PROBES
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_probe_ARoundTripCompletes(uint256 amountIn, uint256 shares, bool zeroForOne) public {
        // Given: The suite's staged core and manipulator.

        // When: The manipulator round trips through the core, then through a vault.
        manipulator.roundTrip(amountIn, shares, zeroForOne, 0);
        manipulator.roundTrip(amountIn, shares, zeroForOne, 2);

        // Then: The round trips were measured at the restored price.
        assertGe(manipulator.ghostRoundTrips(), 1);
        assertEq(manipulator.ghostUnrestored(), 0);
        invariant_manipulationLeavesTheActorNoProfit();
        invariant_manipulationCostsNoStayerAnything();
    }

    /* //////////////////////////////////////////////////////////////
                               INVARIANTS
    ////////////////////////////////////////////////////////////// */

    function invariant_everyRoundTripRestoresThePrice() public view {
        assertEq(manipulator.ghostUnrestored(), 0);
    }

    function invariant_manipulationLeavesTheActorNoProfit() public view {
        assertEq(manipulator.ghostActorGains(), 0);
    }

    function invariant_manipulationCostsNoStayerAnything() public view {
        assertEq(manipulator.ghostStayerLosses(), 0);
    }
}
