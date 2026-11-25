/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { VmSafe } from "@forge-std/Vm.sol";

library Accesses {
    function delegateCallsInto(VmSafe.AccountAccess[] memory accesses, address first, address second)
        internal
        pure
        returns (uint256 count)
    {
        for (uint256 i; i < accesses.length; ++i) {
            if (accesses[i].kind != VmSafe.AccountAccessKind.DelegateCall) continue;
            if (accesses[i].account == first || accesses[i].account == second) ++count;
        }
    }
}
