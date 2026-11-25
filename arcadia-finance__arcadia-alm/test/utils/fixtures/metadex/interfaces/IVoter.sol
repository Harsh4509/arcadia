/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface IVoter {
    struct Point {
        int128 bias;
        int128 slope;
        uint48 ts;
        uint128 permanentStakeBalance;
    }

    function chainStates(uint256 chainId)
        external
        view
        returns (
            Point memory point,
            uint256 ceiling,
            uint256 totalRedeemed,
            uint256 reportedSurplus,
            uint256 cumulativeSuspendedSurplus,
            uint256 surplusSpent,
            uint256 lastIndex,
            uint256 lastTimeIndex,
            uint256 donatedBuffer,
            uint8 status
        );
    function grantRole(bytes32 role, address account) external;
    function registerChain(uint256 chainId) external;
}
