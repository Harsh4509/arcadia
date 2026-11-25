/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../../../core/libraries/logic/ALMCoreViewLogic.sol";
import { CLMath } from "../../../shared/libraries/math/CLMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../interfaces/IALMCore.sol";
import { MetadexOracle } from "../../../shared/libraries/vendored/MetadexOracle.sol";
import { Snapshot, SnapshotLib } from "../../types/Snapshot.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title Base Vault Accounting.
 * @author Pragma Labs
 * @notice The ERC-4626 accounting views of a vault.
 */
abstract contract BaseVaultAccounting {
    using ALMCoreViewLogic for IALMCore;
    using FixedPointMathLib for uint256;
    using SnapshotLib for IALMCore;
    using SnapshotLib for Snapshot;

    /* //////////////////////////////////////////////////////////////
                               PARAMETERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The core the vault is an entry point to.
     * @return core The core.
     */
    function _core() internal view virtual returns (IALMCore core);

    /**
     * @notice The Metadex CL pool of the core.
     * @return pool The pool.
     */
    function _pool() internal view virtual returns (address pool);

    /**
     * @notice The vault whose swap the pool's fee is read for.
     * @return vault The vault.
     */
    function _vault() internal view virtual returns (address vault);

    /**
     * @notice Whether the vault's asset is token0.
     * @return assetIsToken0 True when the asset is token0.
     */
    function _assetIsToken0() internal view virtual returns (bool assetIsToken0);

    /* //////////////////////////////////////////////////////////////
                               ACCOUNTING
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice What the core's whole holding is worth in this vault's asset.
     * @return assets The asset amount.
     */
    function totalAssets() external view returns (uint256 assets) {
        assets = _totalAssets(_core().getSnapshot(_pool(), _vault()));
    }

    /**
     * @notice The shares an asset amount is worth at the vault's own rate.
     * @param assets The asset amount.
     * @return shares The aLP shares, rounded down.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        // Cache the core's snapshot.
        Snapshot memory snapshot = _core().getSnapshot(_pool(), _vault());

        // Calculate the core's holding in the asset.
        uint256 total = _totalAssets(snapshot);

        // Checks.
        if (total == 0) return 0;

        // Convert the assets to shares pro rata.
        shares = assets.fullMulDiv(snapshot.supply, total);
    }

    /**
     * @notice The assets a share amount is worth at the vault's own rate.
     * @param shares The aLP shares.
     * @return assets The asset amount, rounded down.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        // Cache the core's snapshot.
        Snapshot memory snapshot = _core().getSnapshot(_pool(), _vault());

        // Checks.
        if (snapshot.supply == 0) return 0;

        // Convert the shares to assets pro rata.
        assets = shares.fullMulDiv(_totalAssets(snapshot), snapshot.supply);
    }

    /**
     * @notice The core's holding in this vault's asset, the lower of its value at spot and at the TWAP price.
     * @param snapshot The core's snapshot.
     * @return assets The asset amount.
     * @dev A higher price lowers the holding's worth in token0 and raises it in token1.
     */
    function _totalAssets(Snapshot memory snapshot) internal view returns (uint256 assets) {
        // Get the spot and TWAP prices.
        bool assetIsToken0 = _assetIsToken0();
        uint160 sqrtPriceX96 = snapshot.sqrtPriceX96;
        uint160 twapSqrtPriceX96 = TickMath.getSqrtPriceAtTick(MetadexOracle.consult(_pool(), _core().getTwapWindow()));

        // Use the price that values the holding lowest.
        if (assetIsToken0 ? twapSqrtPriceX96 > sqrtPriceX96 : twapSqrtPriceX96 < sqrtPriceX96) {
            sqrtPriceX96 = twapSqrtPriceX96;
        }

        // Calculate the pool tokens in the ranges, the buffer and the uncollected fees.
        (uint256 amount0, uint256 amount1) = snapshot.getAmountsAt(sqrtPriceX96);

        // Calculate the holding in the asset (other pool token converted at that price).
        assets = assetIsToken0
            ? amount0 + CLMath.convert(sqrtPriceX96, false, amount1, false)
            : amount1 + CLMath.convert(sqrtPriceX96, true, amount0, false);
    }
}
