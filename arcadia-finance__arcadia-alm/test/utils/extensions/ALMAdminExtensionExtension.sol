/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ImmutablesExtension } from "./ImmutablesExtension.sol";

contract ALMAdminExtensionExtension is ALMAdminExtension, ImmutablesExtension {
    function SELF_() external view returns (address self) {
        self = SELF;
    }
}
