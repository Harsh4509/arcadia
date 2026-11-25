/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { ImmutablesExtension } from "./ImmutablesExtension.sol";

contract ALMKeeperExtensionExtension is ALMKeeperExtension, ImmutablesExtension {
    function SELF_() external view returns (address self) {
        self = SELF;
    }
}
