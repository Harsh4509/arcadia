/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface IFactoryRegistry {
    function gaugeToFactory(address gauge) external view returns (address factory);
    function gaugeToTarget(address gauge) external view returns (address target);
    function leafVoter() external view returns (address);
    function registerFactories(address gaugeFactory, address targetFactory) external;
    function registerGauge(address gauge, address gaugeFactory, address emissions, address target) external;
    function targetToGauge(address target) external view returns (address gauge);
}
