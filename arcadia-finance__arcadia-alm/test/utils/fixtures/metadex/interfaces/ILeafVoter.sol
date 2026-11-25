/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface ILeafVoter {
    enum ChainStatus {
        None,
        Active,
        Paused,
        Suspended,
        Sunset
    }

    struct TokenSnapshot {
        uint128 staked;
        uint48 stakeEnd;
        bool isPermanent;
    }

    struct GaugeAllocation {
        address gauge;
        uint128 allocated;
        bytes data;
    }

    error ChainNotActiveOrSunset();

    function EMISSIONS_HANDLER() external view returns (address);
    function FACTORY_REGISTRY() external view returns (address);
    function MIN_REDEEM_AMOUNT() external view returns (uint256);
    function ORCHESTRATOR() external view returns (address);
    function RECEIPT_TOKEN() external view returns (address);
    function applyChainAllocation(
        uint256 tokenId,
        uint128 allocationDelta,
        uint256 emissionsPerVP,
        bool refreshEmissionsPerVP,
        bool refreshShape,
        TokenSnapshot calldata snapshot
    ) external;
    function applyGaugeAllocations(
        uint256 tokenId,
        uint48 expiry,
        uint256 emissionsPerVP,
        bool refreshEmissionsPerVP,
        bool refreshShape,
        TokenSnapshot calldata newSnapshot,
        GaugeAllocation[] calldata gauges
    ) external;
    function chainStatus() external view returns (ChainStatus);
    function grantRole(bytes32 role, address account) external;
    function isActivated(address gauge) external view returns (bool);
    function registerGauge(address gauge, bool activate) external;
    function setChainStatus(ChainStatus status) external;
    function settleGauge(address gauge) external returns (uint256 cumulativeRewardShare);
}
