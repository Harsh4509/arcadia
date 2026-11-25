/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { Vaults } from "./Vaults.sol";

/**
 * @notice The immutables of a core and its extensions.
 */
struct CoreParameters {
    int24 tickSpacing;
    address positionManager;
    address routerTrampoline;
    address leafVoter;
    address gaugeFactory;
    address rewardToken;
    bool arbBlockNumber;
    address pool;
    address token0;
    address token1;
    address gauge;
    address feeRecipient;
    address keeperExtension;
    address adminExtension;
    Vaults vaults;
}
