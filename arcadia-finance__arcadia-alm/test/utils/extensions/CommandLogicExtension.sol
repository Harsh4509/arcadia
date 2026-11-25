/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CommandLogic } from "../../../src/core/libraries/logic/CommandLogic.sol";

contract CommandLogicExtension {
    function pausable(uint8 command) external pure returns (bool refused) {
        refused = CommandLogic.pausable(command);
    }
}
