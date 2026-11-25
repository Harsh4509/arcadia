/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { MetadexPositionValue } from "../../../src/shared/libraries/vendored/MetadexPositionValue.sol";

contract MetadexPositionValueExtension {
    function fees(address pool, address positionManager, uint256 tokenId)
        external
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) =
            MetadexPositionValue.fees(pool, IMetadexCLPositionManager(positionManager).positions(tokenId));
    }
}
