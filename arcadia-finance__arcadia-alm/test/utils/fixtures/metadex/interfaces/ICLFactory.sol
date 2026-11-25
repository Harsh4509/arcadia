/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

interface ICLFactory {
    struct FeeTier {
        int24 tickSpacing;
        uint24 fee;
    }

    struct ConstructorParams {
        address owner;
        address swapFeeManager;
        address unstakedFeeManager;
        address voter;
        address poolImplementation;
        address positionManager;
        address factoryRegistry;
        address defaultSwapHook;
        address discountRegistryManager;
        address clPoolTapeManager;
        FeeTier[] initialFeeTiers;
    }

    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96)
        external
        returns (address pool);
    function enableTickSpacing(int24 tickSpacing, uint24 fee) external;
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
    function poolImplementation() external view returns (address);
    function setDefaultUnstakedFee(uint24 defaultUnstakedFee) external;
    function setPoolSwapHook(address[] calldata pools, address[] calldata swapHooks) external;
    function tickSpacingToFee(int24 tickSpacing) external view returns (uint24);
}
