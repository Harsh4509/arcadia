/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

interface IFactoryRegistry {
    function gaugeToTarget(address gauge) external view returns (address target);
}
