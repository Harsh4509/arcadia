/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { INonfungiblePositionManager } from "../../utils/fixtures/metadex/interfaces/INonfungiblePositionManager.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";

/**
 * @notice Drives the two synchronous vaults of "ALMCore" for the invariant suite.
 */
// forge-lint: disable-next-item(unused-return)
contract ALMVaultSyncHandler is BaseHandler {
    using SnapshotLib for IALMCore;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    ALMVaultSync internal immutable SYNC_VAULT0;
    ALMVaultSync internal immutable SYNC_VAULT1;
    INonfungiblePositionManager internal immutable POSITION_MANAGER;

    // The shares the vaults minted.
    uint256 public ghostSharesMinted;
    // The shares the vaults burned.
    uint256 public ghostSharesBurned;
    // The entries and exits that went through while spot sat outside the band around the TWAP.
    uint256 public ghostOutOfBandEntries;
    // The entries and exits tried while spot sat outside the band around the TWAP.
    uint256 public ghostOutOfBandAttempts;
    // The entries a paused core or vault, and the exits a paused vault, accepted.
    uint256 public ghostPausedAccepts;
    // The entries and exits tried while the core or the vault was paused.
    uint256 public ghostPausedAttempts;
    // The state-changing core calls that went through.
    uint256 public ghostCheckpoints;
    // The hidden emissions, net of the protocol fee, the withdraws and redeems forfeited at most.
    uint256 public ghostForfeited;
    // The calls within their max view that reverted for a reason the max views do not accept.
    uint256 public ghostMaxRefusals;
    // The calls whose result fell on the wrong side of their preview.
    uint256 public ghostPreviewBreaks;
    // The pool tokens sweeps moved into the core, and the protocol fees the skim of each sweep booked.
    uint256 public ghostSwept0;
    uint256 public ghostSwept1;
    uint256 public ghostSweepSkimmed0;
    uint256 public ghostSweepSkimmed1;
    // The sweeps that left a pool token in the vault.
    uint256 public ghostSweepLeftovers;
    // The entries that left the supply above the total cap.
    uint256 public ghostTotalCapBreaches;
    // The calls within their max view the pool's tick limit or the token delta limit refused.
    uint256 public ghostCapacityRefusals;
    // The bounded calls whose limit sat one unit past the preview that the limit refused, and those that broke it.
    uint256 public ghostLimitRefusals;
    uint256 public ghostLimitBreaches;
    // The entries and exits that lowered a range's liquidity, or the buffer plus fees, per remaining share.
    uint256 public ghostInKindFalls;

    // True while the call under way meets a paused core or vault, or spot outside the band.
    bool internal blocked;
    bool internal inBand;
    // The hidden emissions, net of the protocol fee, the exit under way forfeits at most.
    uint256 internal forfeited;
    // The limit of the call under way: none, at its preview, or one unit past it.
    uint256 internal limitKind;
    // The core's liquidity per range, buffer plus fees and supply before the call under way.
    uint256[] internal liquidityBefore;
    uint256 internal held0Before;
    uint256 internal held1Before;
    uint256 internal supplyBefore;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ALMCoreHandler coreHandler,
        address syncVault0,
        address syncVault1,
        INonfungiblePositionManager positionManager
    ) {
        ALM_CORE = almCore;
        POSITION_MANAGER = positionManager;
        CORE_HANDLER = coreHandler;
        SYNC_VAULT0 = ALMVaultSync(syncVault0);
        SYNC_VAULT1 = ALMVaultSync(syncVault1);
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function deposit(
        uint256 actorSeed,
        uint256 receiverSeed,
        uint256 assets,
        bool isToken0,
        bool withinMax,
        uint256 limitSeed
    ) external countCall(this.deposit.selector) advanceBlock {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        address receiver = CORE_HANDLER.actorAt(receiverSeed);
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxDeposit(receiver);
            withinMax = withinMax && ceiling > 0;
            assets = bound(assets, 1, withinMax ? ceiling : Constants.MAX_FUZZED_AMOUNT);
        }
        _fund(actor, vault, assets);
        (bool previewed, uint256 preview) =
            _preview(vault, abi.encodeCall(ALMVaultSync.previewDeposit, (assets)), this.deposit.selector, withinMax);
        if (!previewed) return;
        limitKind = bound(limitSeed, 0, 2);
        uint256 minShares = _tighten(preview, true);
        _entryState(vault);
        uint256 balanceBefore = ALM_CORE.balanceOf(receiver);

        vm.prank(actor);
        (bool success, bytes memory reason) = address(vault)
            .call(
                limitKind != 0
                    ? abi.encodeWithSignature("deposit(uint256,address,uint256)", assets, receiver, minShares)
                    : abi.encodeWithSignature("deposit(uint256,address)", assets, receiver)
            );
        if (success) {
            uint256 shares = ALM_CORE.balanceOf(receiver) - balanceBefore;
            ghostCheckpoints++;
            ghostSharesMinted += shares;
            if (shares < preview) ghostPreviewBreaks++;
            if (limitKind != 0 && shares < minShares) ghostLimitBreaches++;
            _countEntry(receiver);
        } else {
            _recordRevert(this.deposit.selector, reason);
            _countRefusal(reason, withinMax, true);
        }

        CORE_HANDLER.countPendingMoves(receiver, receiver);
    }

    function mint(
        uint256 actorSeed,
        uint256 receiverSeed,
        uint256 shares,
        bool isToken0,
        bool withinMax,
        uint256 limitSeed
    ) external countCall(this.mint.selector) advanceBlock {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        address receiver = CORE_HANDLER.actorAt(receiverSeed);
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(receiver);
            withinMax = withinMax && ceiling > 0;
            shares = bound(shares, 1, withinMax ? ceiling : Constants.MAX_FUZZED_AMOUNT);
        }
        (bool previewed, uint256 preview) =
            _preview(vault, abi.encodeCall(ALMVaultSync.previewMint, (shares)), this.mint.selector, withinMax);
        if (!previewed) return;
        _fund(actor, vault, preview);
        limitKind = bound(limitSeed, 0, 2);
        uint256 maxAssets = _tighten(preview, false);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(actor);
        _entryState(vault);

        vm.prank(actor);
        (bool success, bytes memory reason) = address(vault)
            .call(
                limitKind != 0
                    ? abi.encodeWithSignature("mint(uint256,address,uint256)", shares, receiver, maxAssets)
                    : abi.encodeWithSignature("mint(uint256,address)", shares, receiver)
            );
        if (success) {
            uint256 spent = assetsBefore - ERC20Mock(vault.asset()).balanceOf(actor);
            ghostCheckpoints++;
            ghostSharesMinted += shares;
            if (spent > preview) ghostPreviewBreaks++;
            if (limitKind != 0 && spent > maxAssets) ghostLimitBreaches++;
            _countEntry(receiver);
        } else {
            _recordRevert(this.mint.selector, reason);
            _countRefusal(reason, withinMax, false);
        }

        CORE_HANDLER.countPendingMoves(receiver, receiver);
    }

    function withdraw(
        uint256 callerSeed,
        uint256 ownerSeed,
        uint256 receiverSeed,
        uint256 assets,
        bool isToken0,
        bool withinMax,
        uint256 limitSeed
    ) external countCall(this.withdraw.selector) advanceBlock {
        address caller = CORE_HANDLER.actorAt(callerSeed);
        address owner = CORE_HANDLER.actorAt(ownerSeed);
        address receiver = CORE_HANDLER.actorAt(receiverSeed);
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxWithdraw(owner);
            withinMax = withinMax && ceiling > 0;
            assets = bound(assets, 1, withinMax ? ceiling : Constants.MAX_FUZZED_AMOUNT);
        }
        (bool previewed, uint256 preview) =
            _preview(vault, abi.encodeCall(ALMVaultSync.previewWithdraw, (assets)), this.withdraw.selector, withinMax);
        if (!previewed) return;
        if (caller != owner) {
            vm.prank(owner);
            ALM_CORE.approve(caller, preview);
        }
        limitKind = bound(limitSeed, 0, 2);
        uint256 maxShares = _tighten(preview, false);
        _exitState(vault);
        uint256 balanceBefore = ALM_CORE.balanceOf(owner);

        vm.prank(caller);
        (bool success, bytes memory reason) = address(vault)
            .call(
                limitKind != 0
                    ? abi.encodeWithSignature(
                        "withdraw(uint256,address,address,uint256)", assets, receiver, owner, maxShares
                    )
                    : abi.encodeWithSignature("withdraw(uint256,address,address)", assets, receiver, owner)
            );
        if (success) {
            uint256 shares = balanceBefore - ALM_CORE.balanceOf(owner);
            ghostSharesBurned += shares;
            if (shares > preview) ghostPreviewBreaks++;
            if (limitKind != 0 && shares > maxShares) ghostLimitBreaches++;
            _countExit();
        } else {
            _recordRevert(this.withdraw.selector, reason);
            _countRefusal(reason, withinMax, false);
        }

        CORE_HANDLER.countPendingMoves(owner, receiver);
    }

    function redeem(
        uint256 callerSeed,
        uint256 ownerSeed,
        uint256 receiverSeed,
        uint256 shares,
        bool isToken0,
        bool withinMax,
        uint256 limitSeed
    ) external countCall(this.redeem.selector) advanceBlock {
        address caller = CORE_HANDLER.actorAt(callerSeed);
        address owner = CORE_HANDLER.actorAt(ownerSeed);
        address receiver = CORE_HANDLER.actorAt(receiverSeed);
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxRedeem(owner);
            withinMax = withinMax && ceiling > 0;
            shares = bound(shares, 1, withinMax ? ceiling : Constants.MAX_FUZZED_AMOUNT);
        }
        (bool previewed, uint256 preview) =
            _preview(vault, abi.encodeCall(ALMVaultSync.previewRedeem, (shares)), this.redeem.selector, withinMax);
        if (!previewed) return;
        if (caller != owner) {
            vm.prank(owner);
            ALM_CORE.approve(caller, shares);
        }
        limitKind = bound(limitSeed, 0, 2);
        uint256 minAssets = _tighten(preview, true);
        _exitState(vault);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(receiver);

        vm.prank(caller);
        (bool success, bytes memory reason) = address(vault)
            .call(
                limitKind != 0
                    ? abi.encodeWithSignature(
                        "redeem(uint256,address,address,uint256)", shares, receiver, owner, minAssets
                    )
                    : abi.encodeWithSignature("redeem(uint256,address,address)", shares, receiver, owner)
            );
        if (success) {
            uint256 assets = ERC20Mock(vault.asset()).balanceOf(receiver) - assetsBefore;
            ghostSharesBurned += shares;
            if (assets < preview) ghostPreviewBreaks++;
            if (limitKind != 0 && assets < minAssets) ghostLimitBreaches++;
            _countExit();
        } else {
            _recordRevert(this.redeem.selector, reason);
            _countRefusal(reason, withinMax, false);
        }

        CORE_HANDLER.countPendingMoves(owner, receiver);
    }

    function sweep(bool isToken0) external countCall(this.sweep.selector) advanceBlock {
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        ERC20Mock token0 = ERC20Mock(ALM_CORE.token0());
        ERC20Mock token1 = ERC20Mock(ALM_CORE.token1());
        (uint256 held0, uint256 held1) = (token0.balanceOf(address(vault)), token1.balanceOf(address(vault)));
        (uint256 fees0, uint256 fees1) = (ALM_CORE.getProtocolFees0(), ALM_CORE.getProtocolFees1());
        CORE_HANDLER.trackFairShares();
        CORE_HANDLER.watchPending();

        try vault.sweep() {
            ghostCheckpoints++;
            ghostSwept0 += held0;
            ghostSwept1 += held1;
            ghostSweepSkimmed0 += ALM_CORE.getProtocolFees0() - fees0;
            ghostSweepSkimmed1 += ALM_CORE.getProtocolFees1() - fees1;
            if (token0.balanceOf(address(vault)) + token1.balanceOf(address(vault)) != 0) ghostSweepLeftovers++;
        } catch (bytes memory reason) {
            _recordRevert(this.sweep.selector, reason);
        }

        CORE_HANDLER.countPendingMoves(address(0), address(0));
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _preview(ALMVaultSync vault, bytes memory data, bytes4 selector, bool withinMax)
        internal
        returns (bool previewed, uint256 preview)
    {
        bytes memory result;
        (previewed, result) = address(vault).staticcall(data);
        if (previewed) return (previewed, abi.decode(result, (uint256)));
        _recordRevert(selector, result);
        if (withinMax) ghostMaxRefusals++;
    }

    function _fund(address actor, ALMVaultSync vault, uint256 assets) internal {
        ERC20Mock asset = ERC20Mock(vault.asset());
        asset.mint(actor, assets);
        vm.prank(actor);
        asset.approve(address(vault), type(uint256).max);
    }

    function _tighten(uint256 preview, bool up) internal view returns (uint256 limit) {
        if (limitKind != 2) return preview;
        if (up) return preview == type(uint256).max ? preview : preview + 1;
        limit = preview == 0 ? 0 : preview - 1;
    }

    function _entryState(ALMVaultSync vault) internal {
        blocked = ALM_CORE.paused_() || vault.paused();
        _flowState();
    }

    function _exitState(ALMVaultSync vault) internal {
        blocked = vault.paused();
        _flowState();
        forfeited = CORE_HANDLER.forfeitOf(CORE_HANDLER.hiddenEmissions(ALM_CORE.stakedTokenIds()));
    }

    function _flowState() internal {
        inBand = _inBand();
        if (blocked) ghostPausedAttempts++;
        if (!inBand) ghostOutOfBandAttempts++;
        CORE_HANDLER.trackFairShares();
        CORE_HANDLER.watchPending();
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(ALM_CORE.pool_(), address(this));
        delete liquidityBefore;
        for (uint256 i; i < snapshot.ranges.length; ++i) {
            liquidityBefore.push(snapshot.ranges[i].liquidity);
        }
        (held0Before, held1Before, supplyBefore) =
        (snapshot.buffer0 + snapshot.fees0, snapshot.buffer1 + snapshot.fees1, snapshot.supply);
    }

    function _countEntry(address receiver) internal {
        if (blocked) ghostPausedAccepts++;
        if (!inBand) ghostOutOfBandEntries++;
        if (ALM_CORE.totalSupply() > ALM_CORE.totalCap_()) ghostTotalCapBreaches++;
        CORE_HANDLER.countCapBreach(receiver);
        _countInKindFall();
    }

    function _countExit() internal {
        ghostCheckpoints++;
        ghostForfeited += forfeited;
        if (blocked) ghostPausedAccepts++;
        if (!inBand) ghostOutOfBandEntries++;
        _countInKindFall();
    }

    function _countInKindFall() internal {
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(ALM_CORE.pool_(), address(this));
        uint256 supply = snapshot.supply;
        for (uint256 i; i < snapshot.ranges.length; ++i) {
            if (snapshot.ranges[i].liquidity * supplyBefore < liquidityBefore[i] * supply) ghostInKindFalls++;
        }
        if ((snapshot.buffer0 + snapshot.fees0) * supplyBefore < held0Before * supply) ghostInKindFalls++;
        if ((snapshot.buffer1 + snapshot.fees1) * supplyBefore < held1Before * supply) ghostInKindFalls++;
    }

    function _countRefusal(bytes memory reason, bool withinMax, bool isDeposit) internal {
        bytes4 selector = _selectorOf(reason);
        if (
            limitKind != 0
                && (selector == ALMVaultSync.InsufficientOutput.selector
                    || selector == ALMVaultSync.ExcessiveInput.selector)
        ) {
            if (limitKind == 1) ghostPreviewBreaks++;
            else ghostLimitRefusals++;
            return;
        }
        if (!withinMax) return;
        if (isDeposit && selector == ALMCore.ZeroShares.selector) return;
        if (
            selector == SafeCastLib.Overflow.selector
                || keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", "LO"))
        ) {
            ghostCapacityRefusals++;
            return;
        }
        ghostMaxRefusals++;
    }

    function viewsRevert(address holder) external view returns (bool reverted) {
        reverted = _viewsRevert(SYNC_VAULT0, holder) || _viewsRevert(SYNC_VAULT1, holder);
    }

    function roomWhilePaused(address holder) external view returns (bool room) {
        room = _roomWhilePaused(SYNC_VAULT0, holder) || _roomWhilePaused(SYNC_VAULT1, holder);
    }

    function _roomWhilePaused(ALMVaultSync vault, address holder) internal view returns (bool room) {
        if (!vault.paused()) return false;
        room =
            vault.maxDeposit(holder) + vault.maxMint(holder) + vault.maxRedeem(holder) + vault.maxWithdraw(holder) > 0;
    }

    function _viewsRevert(ALMVaultSync vault, address holder) internal view returns (bool reverted) {
        try vault.totalAssets() returns (uint256 totalAssets) {
            try vault.maxDeposit(holder) returns (uint256 maxDeposit) {
                maxDeposit = FixedPointMathLib.min(maxDeposit, totalAssets);
                if (maxDeposit != 0) {
                    try vault.previewDeposit(maxDeposit) { }
                    catch {
                        return true;
                    }
                }
            } catch {
                return true;
            }
            try vault.maxWithdraw(holder) returns (uint256 maxWithdraw) {
                maxWithdraw = FixedPointMathLib.min(maxWithdraw, totalAssets);
                if (maxWithdraw != 0) {
                    try vault.previewWithdraw(maxWithdraw) { }
                    catch {
                        return true;
                    }
                }
                try vault.convertToShares(maxWithdraw) { }
                catch {
                    return true;
                }
            } catch {
                return true;
            }
        } catch {
            return true;
        }
        uint256 supply = ALM_CORE.totalSupply();
        try vault.maxMint(holder) returns (uint256 maxMint) {
            maxMint = FixedPointMathLib.min(maxMint, supply);
            if (maxMint != 0) {
                try vault.previewMint(maxMint) { }
                catch {
                    return true;
                }
            }
        } catch {
            return true;
        }
        try vault.maxRedeem(holder) returns (uint256 maxRedeem) {
            if (maxRedeem != 0) {
                try vault.previewRedeem(maxRedeem) { }
                catch {
                    return true;
                }
            }
        } catch {
            return true;
        }
        try vault.convertToAssets(ALM_CORE.balanceOf(holder)) { }
        catch {
            return true;
        }
    }

    function _inBand() internal view returns (bool inside) {
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) =
            CLMath.getBand(ALM_CORE.meanSqrtPriceX96_(), ALM_CORE.maxSpotFromTwap_());
        inside = sqrtPriceX96 >= sqrtPriceLowerX96 && sqrtPriceX96 <= sqrtPriceUpperX96;
    }

    function _afterAction() internal override {
        CORE_HANDLER.checkMonotone();
    }
}
