/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../core/libraries/logic/ALMCoreViewLogic.sol";
import { BaseVaultAccounting } from "./abstracts/base/BaseVaultAccounting.sol";
import { CalldataLogic } from "./libraries/logic/CalldataLogic.sol";
import { DepositOptimizationMath } from "./libraries/math/DepositOptimizationMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../interfaces/IALMCore.sol";
import { MintOptimizationMath } from "./libraries/math/MintOptimizationMath.sol";
import { PoolLogic } from "../shared/libraries/logic/PoolLogic.sol";
import { RedeemOptimizationMath } from "./libraries/math/RedeemOptimizationMath.sol";
import { Snapshot, SnapshotLib } from "./types/Snapshot.sol";
import { WithdrawOptimizationMath } from "./libraries/math/WithdrawOptimizationMath.sol";

/**
 * @title ALM Sync Extension.
 * @author Pragma Labs
 * @notice The preview, max and accounting views of every synchronous vault on a chain, called with the vault's
 * parameters appended.
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract ALMSyncExtension is BaseVaultAccounting {
    using ALMCoreViewLogic for IALMCore;
    using FixedPointMathLib for uint256;
    using SnapshotLib for IALMCore;
    using SnapshotLib for Snapshot;

    /* //////////////////////////////////////////////////////////////
                               PARAMETERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _core() internal pure override returns (IALMCore core) {
        core = IALMCore(CalldataLogic.decodeCore());
    }

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _pool() internal pure override returns (address pool) {
        pool = CalldataLogic.decodePool();
    }

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _vault() internal view override returns (address vault) {
        vault = msg.sender;
    }

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _assetIsToken0() internal pure override returns (bool assetIsToken0) {
        assetIsToken0 = CalldataLogic.decodeAssetIsToken0();
    }

    /* //////////////////////////////////////////////////////////////
                                PREVIEWS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The aLP a deposit would mint, as a lower bound.
     * @param assets The asset amount paid.
     * @return shares The aLP shares.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        // Calculate the shares the payment mints, including the swap into the other pool token.
        shares = DepositOptimizationMath.previewDeposit(
            _core().getSnapshot(_pool(), _vault()), _pool(), _assetIsToken0(), assets
        );
    }

    /**
     * @notice The asset amount a mint would cost, as an upper bound.
     * @param shares The aLP shares.
     * @return assets The asset amount.
     */
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        // Calculate the payment the mint takes, including the swap of the payment into the other pool token.
        assets =
            MintOptimizationMath.previewMint(_core().getSnapshot(_pool(), _vault()), _pool(), _assetIsToken0(), shares);
    }

    /**
     * @notice The asset amount a redeem would pay out, as a lower bound.
     * @param shares The aLP shares burned.
     * @return assets The asset amount.
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        // Calculate the assets the redeem pays out, including the sale of the other pool token for the asset.
        assets = RedeemOptimizationMath.previewRedeem(
            _core().getSnapshot(_pool(), _vault()), _pool(), !_assetIsToken0(), shares, 0
        );
    }

    /* //////////////////////////////////////////////////////////////
                                  LIMITS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The most aLP an account may mint here.
     * @param receiver The account the shares would be minted to.
     * @return shares The aLP shares.
     */
    function maxMint(address receiver) external view returns (uint256 shares) {
        // Get the shares the receiver may still mint under the core's caps.
        uint256 sqrtPriceLimitX96;
        (shares, sqrtPriceLimitX96) = _maxShares(receiver, true);
        if (shares == 0) return 0;

        // Cap the shares at the most whose swap into the other pool token stays within the price limit.
        shares = FixedPointMathLib.min(
            shares,
            MintOptimizationMath.maxMint(
                _core().getSnapshot(_pool(), _vault()), _pool(), sqrtPriceLimitX96, _assetIsToken0()
            )
        );
    }

    /**
     * @notice The most an account may deposit here.
     * @param receiver The account the shares would be minted to.
     * @return assets The asset amount.
     */
    function maxDeposit(address receiver) external view returns (uint256 assets) {
        // Get the shares the receiver may still mint under the core's caps.
        (uint256 shares, uint256 sqrtPriceLimitX96) = _maxShares(receiver, true);
        if (shares == 0) return 0;

        // Calculate the most payment a deposit of those shares takes, including the swap into the other pool token.
        assets = DepositOptimizationMath.maxDeposit(
            _core().getSnapshot(_pool(), _vault()), _pool(), sqrtPriceLimitX96, _assetIsToken0(), shares
        );
    }

    /**
     * @notice The most aLP an account may redeem here.
     * @param owner The account the shares would be burned from.
     * @return shares The aLP shares.
     */
    function maxRedeem(address owner) external view returns (uint256 shares) {
        // Get the owner's shares.
        (shares,) = _maxShares(owner, false);
        if (shares == 0) return 0;

        // Cap the shares at the most whose sale of the other pool token stays within the max swap cost.
        shares = RedeemOptimizationMath.maxRedeem(
            _core().getSnapshot(_pool(), _vault()), _pool(), !_assetIsToken0(), shares
        );
    }

    /**
     * @notice The most an account may withdraw here.
     * @param owner The account the shares would be burned from.
     * @return assets The asset amount.
     */
    function maxWithdraw(address owner) external view returns (uint256 assets) {
        // Get the owner's shares.
        (uint256 shares,) = _maxShares(owner, false);
        if (shares == 0) return 0;

        // Calculate the most assets a withdraw of those shares pays out, including the sale of the other pool token.
        assets = WithdrawOptimizationMath.maxWithdraw(
            _core().getSnapshot(_pool(), _vault()), _pool(), !_assetIsToken0(), shares
        );
    }

    /**
     * @notice The shares a max view starts from, zero when the pool cannot be quoted or its fee read.
     * @param account The account the shares would be minted to or burned from.
     * @param isEntry True for the shares the account may mint, false for the shares it holds.
     * @return shares The aLP shares.
     * @return sqrtPriceLimitX96 The square root of the price an entry swap may move to, with 96 binary precision.
     */
    function _maxShares(address account, bool isEntry)
        internal
        view
        returns (uint256 shares, uint256 sqrtPriceLimitX96)
    {
        // Checks.
        bool quotable;
        (quotable,, sqrtPriceLimitX96) = _core().quotable(_pool(), _assetIsToken0(), false);
        if (!quotable) return (0, 0);
        (bool ok,) = PoolLogic.tryFee(_pool());
        if (!ok) return (0, 0);

        // Get the shares the account may mint under the core's caps, or the shares it holds.
        shares = isEntry ? _core().maxMint(account) : _core().balanceOf(account);
    }
}
