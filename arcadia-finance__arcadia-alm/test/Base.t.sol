/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Users } from "./utils/Types.sol";

/**
 * @notice Common logic needed by all tests.
 */
abstract contract Base_Test is Test {
    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    Users internal users;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual {
        users = Users({
            owner: createUser("owner"),
            admin: createUser("admin"),
            guardian: createUser("guardian"),
            steward: createUser("steward"),
            keeper: createUser("keeper"),
            liquidityProvider: createUser("liquidityProvider"),
            feeRecipient: createUser("feeRecipient"),
            unprivilegedAddress: createUser("unprivilegedAddress")
        });
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr(name));
        vm.deal(user, 100 ether);
    }
}
