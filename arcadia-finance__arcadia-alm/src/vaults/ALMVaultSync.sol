/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../core/libraries/logic/ALMCoreViewLogic.sol";
import { BaseVault } from "./abstracts/base/BaseVault.sol";
import { DepositOptimizationMath } from "./libraries/math/DepositOptimizationMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../interfaces/IALMCore.sol";
import { IBaseFactory } from "../interfaces/IBaseFactory.sol";
import { IMetadexCLPool } from "../interfaces/IMetadexCLPool.sol";
import { MintOptimizationMath } from "./libraries/math/MintOptimizationMath.sol";
import { PoolLogic } from "../shared/libraries/logic/PoolLogic.sol";
import { ReentrancyLock } from "../shared/abstracts/mixins/ReentrancyLock.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Snapshot, SnapshotLib } from "./types/Snapshot.sol";
import { VaultParameters } from "./types/VaultParameters.sol";
import { WithdrawOptimizationMath } from "./libraries/math/WithdrawOptimizationMath.sol";

/**
 * @title ALM Vault Sync.
 * @author Pragma Labs
 * @notice Deposits and withdraws one pool token, swapping against the pool for the other pool token.
 */
// forge-lint: disable-next-item(missing-events-access-control, reentrancy-events, uninitialized-local, unsafe-typecast, unused-return)
contract ALMVaultSync is ReentrancyLock, BaseVault {
    using ALMCoreViewLogic for IALMCore;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using SnapshotLib for IALMCore;
    using SnapshotLib for Snapshot;

    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    // The extension that holds the preview, max and accounting views of every synchronous vault on the chain.
    address internal immutable SYNC_EXTENSION;
    // The token0 of the pool.
    address internal immutable TOKEN0;
    // The token1 of the pool.
    address internal immutable TOKEN1;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event Swept(uint256 amount0, uint256 amount1);

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error ExcessiveInput();
    error InsufficientOutput();
    error OnlyPool();
    error PriceDeviation();

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() {
        VaultParameters memory params = IBaseFactory(msg.sender).vaultParameters();
        SYNC_EXTENSION = params.syncExtension;
        TOKEN0 = IMetadexCLPool(POOL).token0();
        TOKEN1 = IMetadexCLPool(POOL).token1();

        TOKEN0.safeApproveWithRetry(address(ALM_CORE), type(uint256).max);
        TOKEN1.safeApproveWithRetry(address(ALM_CORE), type(uint256).max);
    }

    /* //////////////////////////////////////////////////////////////
                                  ENTRY
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Deposits assets and mints shares.
     * @param assets The asset amount paid.
     * @param receiver The account the shares are minted to.
     * @return shares The aLP shares minted.
     * @dev Deviates from ERC-4626: refunds the unused assets.
     * @dev Keeps the swap within the core's max swap cost.
     */
    function deposit(uint256 assets, address receiver) external nonReentrant whenNotPaused returns (uint256 shares) {
        shares = _deposit(assets, receiver, true);
    }

    /**
     * @notice Deposits assets and mints shares.
     * @param assets The asset amount paid.
     * @param receiver The account the shares are minted to.
     * @param minShares The least aLP the caller accepts.
     * @return shares The aLP shares minted.
     */
    function deposit(uint256 assets, address receiver, uint256 minShares)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        shares = _deposit(assets, receiver, false);

        // Checks.
        if (shares < minShares) revert InsufficientOutput();
    }

    /**
     * @notice Swaps part of the assets for the other pool token and mints shares with both.
     * @param assets The asset amount paid.
     * @param receiver The account the shares are minted to.
     * @param bounded True to stop the swap at the core's max swap cost.
     * @return shares The aLP shares minted.
     */
    function _deposit(uint256 assets, address receiver, bool bounded) internal returns (uint256 shares) {
        // Nothing mints nothing.
        if (assets == 0) return 0;

        // Calculate the swap of the payment into the other pool token and the shares it mints.
        Snapshot memory snapshot = ALM_CORE.getSnapshot(POOL, address(this));
        (uint160 sqrtPriceLimitX96, uint256 amountSwapIn, uint256 amountSwapOut) =
            DepositOptimizationMath.computeSwap(snapshot, POOL, ASSET_IS_TOKEN0, assets);
        shares = snapshot.getMintShares(sqrtPriceLimitX96, assets - amountSwapIn, amountSwapOut, ASSET_IS_TOKEN0);

        // Swap and mint.
        _swapAndMint(snapshot, sqrtPriceLimitX96, assets, amountSwapOut, shares, receiver, bounded);
    }

    /**
     * @notice Mints shares for assets, with previewMint at execution as the maximum.
     * @param shares The aLP shares minted.
     * @param receiver The account the shares are minted to.
     * @return assets The asset amount paid.
     * @dev The maximum is read in the same transaction and does not protect against an earlier price move.
     * @dev Keeps the swap within the core's max swap cost.
     */
    function mint(uint256 shares, address receiver) external nonReentrant whenNotPaused returns (uint256 assets) {
        assets = _mint(shares, receiver, true);
    }

    /**
     * @notice Mints shares for assets.
     * @param shares The aLP shares minted.
     * @param receiver The account the shares are minted to.
     * @param maxAssets The most the caller pays.
     * @return assets The asset amount paid.
     */
    function mint(uint256 shares, address receiver, uint256 maxAssets)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        assets = _mint(shares, receiver, false);

        // Checks.
        if (assets > maxAssets) revert ExcessiveInput();
    }

    /**
     * @notice Swaps assets for the other pool token the mint needs and mints shares with both.
     * @param shares The aLP shares minted.
     * @param receiver The account the shares are minted to.
     * @param bounded True to stop the swap at the core's max swap cost.
     * @return assets The asset amount paid.
     */
    function _mint(uint256 shares, address receiver, bool bounded) internal returns (uint256 assets) {
        // Nothing costs nothing.
        if (shares == 0) return 0;

        // Calculate the swap of the payment into the other pool token and the payment it takes.
        Snapshot memory snapshot = ALM_CORE.getSnapshot(POOL, address(this));
        (uint160 sqrtPriceLimitX96, uint256 amountSwapIn, uint256 amountSwapOut) =
            MintOptimizationMath.computeSwap(snapshot, POOL, ASSET_IS_TOKEN0, shares);
        (uint256 amountMintIn,,) = snapshot.getMintAmounts(sqrtPriceLimitX96, shares, ASSET_IS_TOKEN0);

        // Swap and mint.
        assets = _swapAndMint(
            snapshot, sqrtPriceLimitX96, amountSwapIn + amountMintIn, amountSwapOut, shares, receiver, bounded
        );
    }

    /**
     * @notice Pulls the payment, swaps part of it for the other pool token and mints shares with both.
     * @param snapshot The core's snapshot before the swap.
     * @param sqrtPriceLimitX96 The square root of the price the swap stops at, with 96 binary precision.
     * @param balanceIn The asset amount pulled from the caller.
     * @param amountSwapOut The other pool token the swap buys.
     * @param shares The aLP shares minted.
     * @param receiver The account the shares are minted to.
     * @param bounded True to stop the swap at the core's max swap cost.
     * @return assets The asset amount paid.
     * @dev Refunds the unused asset.
     */
    function _swapAndMint(
        Snapshot memory snapshot,
        uint160 sqrtPriceLimitX96,
        uint256 balanceIn,
        uint256 amountSwapOut,
        uint256 shares,
        address receiver,
        bool bounded
    ) internal returns (uint256 assets) {
        // Pull the payment.
        ASSET.safeTransferFrom(msg.sender, address(this), balanceIn);

        // Swap part of the payment for the other pool token, at most to the preview's end price.
        uint256 amountSwapIn;
        if (sqrtPriceLimitX96 != snapshot.sqrtPriceX96) {
            // Keep the swap within the core's max swap cost.
            if (bounded) {
                sqrtPriceLimitX96 = ASSET_IS_TOKEN0
                    ? uint160(FixedPointMathLib.max(sqrtPriceLimitX96, snapshot.getSwapCostLimit(true)))
                    : uint160(FixedPointMathLib.min(sqrtPriceLimitX96, snapshot.getSwapCostLimit(false)));
            }
            uint256 amountOut;
            // Unchecked: amountSwapOut is a non-negative int256 value.
            unchecked {
                // The pool rejects a zero output, so a swap that only moves the price to its limit asks for one wei.
                (amountSwapIn, amountOut) = _swap(
                    ASSET_IS_TOKEN0,
                    -SafeCastLib.toInt256(FixedPointMathLib.max(amountSwapOut, 1)),
                    sqrtPriceLimitX96,
                    address(this)
                );
            }
            if (amountOut < amountSwapOut) revert InsufficientOutput();
        }

        // Mint the shares to the receiver, paid with the pool tokens held by this vault.
        uint256 amountMintOut;
        {
            (uint256 amount0, uint256 amount1) = ALM_CORE.mint(shares, receiver);
            uint256 amountMintIn;
            (amountMintIn, amountMintOut) = ASSET_IS_TOKEN0 ? (amount0, amount1) : (amount1, amount0);
            assets = amountSwapIn + amountMintIn;

            // Checks: the mint may only use what is left of the payment and what the swap bought.
            if (assets > balanceIn || amountMintOut > amountSwapOut) revert ExcessiveInput();

            // Transfer the unused asset to the caller.
            uint256 refund;
            // Unchecked: the check above bounds assets by balanceIn.
            unchecked {
                refund = balanceIn - assets;
            }
            if (refund > 0) ASSET.safeTransfer(msg.sender, refund);
        }

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /* //////////////////////////////////////////////////////////////
                                  EXIT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Redeems shares for assets, without a minimum.
     * @param shares The aLP shares burned.
     * @param receiver The account the assets go to.
     * @param owner The account the shares are burned from.
     * @return assets The asset amount paid out.
     * @dev Keeps the sale within the core's max swap cost.
     */
    function redeem(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        assets = _burnAndSwap(shares, receiver, owner, true);
    }

    /**
     * @notice Redeems shares for assets.
     * @param shares The aLP shares burned.
     * @param receiver The account the assets go to.
     * @param owner The account the shares are burned from.
     * @param minAssets The least the caller accepts.
     * @return assets The asset amount paid out.
     */
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        assets = _burnAndSwap(shares, receiver, owner, false);

        // Checks.
        if (assets < minAssets) revert InsufficientOutput();
    }

    /**
     * @notice Withdraws assets for shares, with previewWithdraw at execution as the maximum.
     * @param assets The asset amount asked for.
     * @param receiver The account the assets go to.
     * @param owner The account the shares are burned from.
     * @return shares The aLP shares burned.
     * @dev The maximum is read in the same transaction and does not protect against an earlier price move.
     * @dev Deviates from ERC-4626: sells all the other pool token the burn releases and pays at least assets.
     * @dev Keeps the sale within the core's max swap cost.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        shares = _withdraw(assets, receiver, owner, true);
    }

    /**
     * @notice Withdraws assets for shares.
     * @param assets The asset amount asked for.
     * @param receiver The account the assets go to.
     * @param owner The account the shares are burned from.
     * @param maxShares The most aLP the caller burns.
     * @return shares The aLP shares burned.
     * @dev Deviates from ERC-4626: sells all the other pool token the burn releases and pays at least assets.
     */
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxShares)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        shares = _withdraw(assets, receiver, owner, false);

        // Checks.
        if (shares > maxShares) revert ExcessiveInput();
    }

    /**
     * @notice Redeems the shares a withdraw of assets burns.
     * @param assets The asset amount asked for.
     * @param receiver The account the assets go to.
     * @param owner The account the shares are burned from.
     * @param bounded True to stop the sale at the core's max swap cost.
     * @return shares The aLP shares burned.
     */
    function _withdraw(uint256 assets, address receiver, address owner, bool bounded)
        internal
        returns (uint256 shares)
    {
        // Calculate the shares to burn for the assets.
        shares = WithdrawOptimizationMath.previewWithdraw(
            ALM_CORE.getSnapshot(POOL, address(this)), POOL, !ASSET_IS_TOKEN0, assets
        );

        // Redeem them, selling all the other pool token the burn releases, and check the payout covers the assets.
        if (_burnAndSwap(shares, receiver, owner, bounded) < assets) revert InsufficientOutput();
    }

    /**
     * @notice Burns shares and swaps the other pool token received for assets.
     * @param shares The aLP shares burned.
     * @param receiver The account the assets go to.
     * @param owner The account the shares are burned from.
     * @param bounded True to stop the sale at the core's max swap cost.
     * @return assets The asset amount paid out.
     */
    function _burnAndSwap(uint256 shares, address receiver, address owner, bool bounded)
        internal
        returns (uint256 assets)
    {
        // Checks.
        (bool quotable, uint160 sqrtPriceX96,) = ALM_CORE.quotable(POOL, ASSET_IS_TOKEN0, false);
        if (!quotable) revert PriceDeviation();

        // Burn the owner's shares, with the asset sent to the receiver and the other pool token to this vault.
        uint256 amountBurnOut;
        uint256 amountBurnIn;
        {
            (uint256 amount0, uint256 amount1) = ALM_CORE.trustedBurn(shares, receiver, owner, msg.sender);
            (amountBurnOut, amountBurnIn) = ASSET_IS_TOKEN0 ? (amount0, amount1) : (amount1, amount0);
        }

        // If the burn released the other pool token, sell all of it for the asset to the receiver.
        uint256 amountSwapOut;
        if (amountBurnIn > 0) {
            uint160 sqrtPriceLimitX96 = bounded
                ? SnapshotLib.getSwapCostLimit(
                    sqrtPriceX96, IMetadexCLPool(POOL).fee(), ALM_CORE.getMaxSwapCostBps(), !ASSET_IS_TOKEN0
                )
                : PoolLogic.sqrtPriceLimit(!ASSET_IS_TOKEN0);
            uint256 amountSwapIn;
            (amountSwapIn, amountSwapOut) =
                _swap(!ASSET_IS_TOKEN0, SafeCastLib.toInt256(amountBurnIn), sqrtPriceLimitX96, receiver);
            if (amountSwapIn < amountBurnIn) revert InsufficientOutput();
        }
        assets = amountBurnOut + amountSwapOut;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /* //////////////////////////////////////////////////////////////
                                  SWAPS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Pays the pool the input of a swap this vault started.
     * @param amount0Delta The token0 the pool is owed, negative when the pool owes it.
     * @param amount1Delta The token1 the pool is owed, negative when the pool owes it.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (msg.sender != POOL) revert OnlyPool();

        if (amount0Delta > 0) TOKEN0.safeTransfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) TOKEN1.safeTransfer(msg.sender, uint256(amount1Delta));
    }

    /**
     * @notice Swaps against the pool, up to a price limit.
     * @param zeroForOne True to sell token0 for token1.
     * @param amountSpecified The amount swapped, positive for an exact input and negative for an exact output.
     * @param sqrtPriceLimitX96 The price the swap stops at.
     * @param receiver The account the pool pays the output to.
     * @return amountIn The token amount the pool took.
     * @return amountOut The token amount the pool gave.
     */
    function _swap(bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, address receiver)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        // Swap against the pool.
        (int256 amount0, int256 amount1) =
            IMetadexCLPool(POOL).swap(receiver, zeroForOne, amountSpecified, sqrtPriceLimitX96, "");

        // Calculate the pool token paid to the pool and the pool token received from it.
        (int256 deltaIn, int256 deltaOut) = zeroForOne ? (amount0, amount1) : (amount1, amount0);
        amountIn = uint256(deltaIn);
        amountOut = uint256(-deltaOut);
    }

    /* //////////////////////////////////////////////////////////////
                                PREVIEWS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The aLP a deposit would mint, as a lower bound.
     * param assets The asset amount paid.
     * @return The aLP shares.
     */
    function previewDeposit(uint256) external view returns (uint256) {
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The asset amount a mint would cost, as an upper bound.
     * param shares The aLP shares.
     * @return The asset amount.
     */
    function previewMint(uint256) external view returns (uint256) {
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The aLP a withdraw burns.
     * @param assets The asset amount asked for.
     * @return shares The aLP shares.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
        // Calculate the shares the withdraw burns, including the sale of the other pool token for the asset.
        shares = WithdrawOptimizationMath.previewWithdraw(
            ALM_CORE.getSnapshot(POOL, address(this)), POOL, !ASSET_IS_TOKEN0, assets
        );
    }

    /**
     * @notice The asset amount a redeem would pay out, as a lower bound.
     * param shares The aLP shares burned.
     * @return The asset amount.
     */
    function previewRedeem(uint256) external view returns (uint256) {
        _forward(SYNC_EXTENSION);
    }

    /* //////////////////////////////////////////////////////////////
                               HOUSEKEEPING
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sends this vault's token balances to the core.
     * @return amount0 The token0 swept.
     * @return amount1 The token1 swept.
     */
    function sweep() external nonReentrant returns (uint256 amount0, uint256 amount1) {
        // Transfer this vault's pool tokens to the core.
        amount0 = _sweep(TOKEN0);
        amount1 = _sweep(TOKEN1);

        // Core accrues the received pool tokens to the protocol.
        ALM_CORE.skim();

        emit Swept(amount0, amount1);
    }

    /**
     * @notice Sends this vault's balance of a token to the core.
     * @param token The token swept.
     * @return amount The amount swept.
     */
    function _sweep(address token) internal returns (uint256 amount) {
        amount = token.balanceOf(address(this));
        if (amount > 0) token.safeTransfer(address(ALM_CORE), amount);
    }

    /* //////////////////////////////////////////////////////////////
                                  LIMITS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The most an account may deposit here.
     * param receiver The account the shares would be minted to.
     * @return The asset amount.
     */
    function maxDeposit(address) external view returns (uint256) {
        if (paused) return 0;
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The most aLP an account may mint here.
     * param receiver The account the shares would be minted to.
     * @return The aLP shares.
     */
    function maxMint(address) external view returns (uint256) {
        if (paused) return 0;
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The most aLP an account may redeem here.
     * param owner The account the shares would be burned from.
     * @return The aLP shares.
     */
    function maxRedeem(address) external view returns (uint256) {
        if (paused) return 0;
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The most an account may withdraw here.
     * param owner The account the shares would be burned from.
     * @return The asset amount.
     */
    function maxWithdraw(address) external view returns (uint256) {
        if (paused) return 0;
        _forward(SYNC_EXTENSION);
    }

    /* //////////////////////////////////////////////////////////////
                                ACCOUNTING
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice What the core's whole holding is worth in this vault's asset.
     * @return The asset amount.
     */
    function totalAssets() external view returns (uint256) {
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The shares an asset amount is worth at the vault's own rate.
     * param assets The asset amount.
     * @return The aLP shares, rounded down.
     */
    function convertToShares(uint256) external view returns (uint256) {
        _forward(SYNC_EXTENSION);
    }

    /**
     * @notice The assets a share amount is worth at the vault's own rate.
     * param shares The aLP shares.
     * @return The asset amount, rounded down.
     */
    function convertToAssets(uint256) external view returns (uint256) {
        _forward(SYNC_EXTENSION);
    }

    /* //////////////////////////////////////////////////////////////
                               FORWARDING
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Forwards the call to the sync extension with this vault's parameters appended, and returns its result.
     * @param extension The sync extension.
     */
    function _forward(address extension) internal view {
        bool assetIsToken0 = ASSET_IS_TOKEN0;
        address core = address(ALM_CORE);
        address pool = POOL;
        assembly {
            let size := calldatasize()
            calldatacopy(0, 0, size)
            mstore(size, assetIsToken0)
            mstore(add(size, 0x20), core)
            mstore(add(size, 0x40), pool)
            mstore(add(size, 0x60), 0x60)
            let success := staticcall(gas(), extension, 0, add(size, 0x80), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}
