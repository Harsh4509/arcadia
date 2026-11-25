/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The events logged at the core's address.
 */
interface IALMCoreEvents {
    event Burn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );
    event CapExemptSet(address indexed account, bool exempt);
    event DepositCanceled(address indexed vault, address indexed controller, uint256 assets);
    event DepositCleared(address indexed vault, address indexed controller, uint256 assets);
    event DepositEpochSettled(address indexed vault, uint32 indexed epoch, uint256 assets, uint256 shares);
    event DeviationSet(
        uint32 twapWindow, uint256 maxSpotFromTwap, uint256 maxSpotFromTrusted, uint256 maxTwapFromTrusted
    );
    event EmissionsClaimed(address indexed account, uint256 amountReward);
    event FeesCollected(uint256 fees0, uint256 fees1);
    event Mint(address indexed caller, address indexed receiver, uint256 shares, uint256 amount0, uint256 amount1);
    event PausedSet(bool paused);
    event PerUserCapSet(uint256 cap);
    event PlanExecuted(
        uint256 commandCount,
        uint160 trustedSqrtPriceX96,
        uint256 valueBefore,
        uint256 valueAfter,
        uint256 supplyAfter,
        int256 swapDelta0,
        int256 swapDelta1
    );
    event PlanLimitsSet(uint16 maxShortfallBps, uint16 maxSwapCostBps, uint32 minPlanInterval);
    event ProtocolFeesPaid(uint256 amount0, uint256 amount1, uint256 amountReward);
    event ProtocolFeesSet(uint16 protocolEmissionFeeBps, uint16 protocolSwapFeeBps, address feeRecipient);
    event RangeCapSet(uint8 cap);
    event RangeClosed(uint256 indexed index, uint256 tokenId);
    event RangeOpened(uint256 indexed index, int24 tickLower, int24 tickUpper, uint256 tokenId, uint128 liquidity);
    event RedeemCanceled(address indexed vault, address indexed controller, uint256 shares);
    event RedeemCleared(address indexed vault, address indexed controller, uint256 shares);
    event RedeemEpochSettled(address indexed vault, uint32 indexed epoch, uint256 assets, uint256 shares);
    event RewardPerShareUpdated(uint256 rewardPerShare);
    event Seeded(address indexed receiver, uint256 shares, uint256 amount0, uint256 amount1);
    event Skimmed(uint256 amount0, uint256 amount1);
    event Staked(uint256 indexed index, uint256 tokenId, uint128 liquidity);
    event TotalCapSet(uint256 cap);
    event Unstaked(uint256 indexed index, uint256 tokenId);
    event VaultsSet(address indexed syncVault0, address indexed syncVault1, address asyncVault0, address asyncVault1);
    event VaultUpdate(address indexed asset, address vault);
}
