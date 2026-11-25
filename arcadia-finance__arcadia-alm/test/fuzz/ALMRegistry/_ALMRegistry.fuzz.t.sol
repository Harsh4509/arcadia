/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMRegistry } from "../../../src/registry/ALMRegistry.sol";
import { Constants } from "../../utils/Constants.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";

/**
 * @notice Common logic needed by all "ALMRegistry" fuzz tests.
 */
abstract contract ALMRegistry_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    struct RegistryState {
        address factory;
        address lens;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMRegistry internal registry;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        registry = new ALMRegistry(users.owner);
    }

    /* //////////////////////////////////////////////////////////////
                             REGISTRY STATE
    ////////////////////////////////////////////////////////////// */

    function givenValidRegistryState(RegistryState[] memory registryState, uint256 least, uint256 most)
        internal
        returns (RegistryState[] memory valid)
    {
        // And: A number of factories within the bounds, labelled ones past the fuzzed.
        valid = new RegistryState[](bound(registryState.length, least, most));
        for (uint256 i; i < valid.length; ++i) {
            valid[i] = i < registryState.length
                ? registryState[i]
                : RegistryState({
                    factory: makeAddr(string.concat("factory", vm.toString(i))),
                    lens: makeAddr(string.concat("lens", vm.toString(i)))
                });
        }

        // And: Non-zero factories and lenses, each factory listed once.
        for (uint256 i; i < valid.length; ++i) {
            vm.assume(valid[i].factory != address(0) && valid[i].lens != address(0));
            vm.assume(valid[i].factory != Constants.SET_ZERO_SENTINEL);
            for (uint256 j; j < i; ++j) {
                vm.assume(valid[i].factory != valid[j].factory);
            }
        }
    }

    function setRegistryState(RegistryState[] memory registryState) internal {
        vm.startPrank(users.owner);
        for (uint256 i; i < registryState.length; ++i) {
            registry.registerFactory(registryState[i].factory, registryState[i].lens);
        }
        vm.stopPrank();
    }
}
