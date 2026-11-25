/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexOracle } from "../../../src/shared/libraries/vendored/MetadexOracle.sol";

contract MetadexOracleExtension {
    function consult(address pool, uint32 secondsAgo) external view returns (int24 arithmeticMeanTick) {
        arithmeticMeanTick = MetadexOracle.consult(pool, secondsAgo);
    }
}
