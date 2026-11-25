/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Plan } from "../../utils/Plan.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Enters and leaves "ALMCore" in one action on every entry path, for the invariant suite.
 */
// forge-lint: disable-next-item(unused-return)
contract RoundTripHandler is BaseHandler {
    using ALMCoreViewLogic for IALMCore;
    using Plan for Plan.Steps;
    using SnapshotLib for IALMCore;
    using SnapshotLib for Snapshot;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    address internal immutable KEEPER;
    ALMVaultSync internal immutable SYNC_VAULT0;
    ALMVaultSync internal immutable SYNC_VAULT1;
    ALMVaultAsync internal immutable ASYNC_VAULT0;
    ALMVaultAsync internal immutable ASYNC_VAULT1;

    // The round trips that completed, by path.
    uint256 public ghostSyncDepositTrips;
    uint256 public ghostSyncMintTrips;
    uint256 public ghostCoreTrips;
    uint256 public ghostAsyncTrips;
    // The round trips that left the actor more than it put in.
    uint256 public ghostRoundTripGains;
    uint256 public ghostSharesMinted;
    uint256 public ghostSharesBurned;
    // The state-changing core calls that went through.
    uint256 public ghostCheckpoints;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ALMCoreHandler coreHandler,
        address keeper,
        address syncVault0,
        address syncVault1
    ) {
        ALM_CORE = almCore;
        CORE_HANDLER = coreHandler;
        KEEPER = keeper;
        SYNC_VAULT0 = ALMVaultSync(syncVault0);
        SYNC_VAULT1 = ALMVaultSync(syncVault1);
        ASYNC_VAULT0 = ALMVaultAsync(almCore.asyncVault_(almCore.token0()));
        ASYNC_VAULT1 = ALMVaultAsync(almCore.asyncVault_(almCore.token1()));
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function syncDepositRedeem(uint256 actorSeed, uint256 assets, bool isToken0)
        external
        countCall(this.syncDepositRedeem.selector)
        advanceBlock
    {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        uint256 ceiling = IALMSyncExtension(address(vault)).maxDeposit(actor);
        if (ceiling == 0) return;
        {
            uint256 floor = 1;
            try vault.previewMint(2) returns (uint256 twoShares) {
                floor = twoShares;
            } catch { }
            assets = bound(assets, FixedPointMathLib.min(floor, ceiling), ceiling);
        }
        ERC20Mock asset = _fund(actor, address(vault), assets);
        _watch();

        uint256 balanceBefore = ALM_CORE.balanceOf(actor);
        uint256 assetsIn = asset.balanceOf(actor);
        vm.prank(actor);
        try vault.deposit(assets, actor) { }
        catch (bytes memory reason) {
            _recordRevert(this.syncDepositRedeem.selector, reason);
            return _settleWatch(actor);
        }
        assetsIn -= asset.balanceOf(actor);
        uint256 shares = ALM_CORE.balanceOf(actor) - balanceBefore;
        (ghostCheckpoints, ghostSharesMinted) = (ghostCheckpoints + 1, ghostSharesMinted + shares);
        if (shares == 0) return _settleWatch(actor);

        uint256 assetsBefore = asset.balanceOf(actor);
        vm.prank(actor);
        try vault.redeem(shares, actor, actor) {
            (ghostCheckpoints, ghostSharesBurned) = (ghostCheckpoints + 1, ghostSharesBurned + shares);
            ghostSyncDepositTrips++;
            if (asset.balanceOf(actor) - assetsBefore > assetsIn) ghostRoundTripGains++;
        } catch (bytes memory reason) {
            _recordRevert(this.syncDepositRedeem.selector, reason);
        }
        _settleWatch(actor);
    }

    function syncMintWithdraw(uint256 actorSeed, uint256 shares, bool isToken0)
        external
        countCall(this.syncMintWithdraw.selector)
        advanceBlock
    {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        ALMVaultSync vault = isToken0 ? SYNC_VAULT0 : SYNC_VAULT1;
        uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(actor);
        if (ceiling == 0) return;
        shares = bound(shares, 1, ceiling);
        (bool previewed, bytes memory result) =
            address(vault).staticcall(abi.encodeCall(ALMVaultSync.previewMint, (shares)));
        if (!previewed) return _recordRevert(this.syncMintWithdraw.selector, result);
        uint256 funded = abi.decode(result, (uint256));
        ERC20Mock asset = _fund(actor, address(vault), funded);
        _watch();

        uint256 assetsIn = asset.balanceOf(actor);
        vm.prank(actor);
        try vault.mint(shares, actor) { }
        catch (bytes memory reason) {
            _recordRevert(this.syncMintWithdraw.selector, reason);
            return _settleWatch(actor);
        }
        assetsIn -= asset.balanceOf(actor);
        (ghostCheckpoints, ghostSharesMinted) = (ghostCheckpoints + 1, ghostSharesMinted + shares);

        uint256 balanceBefore = ALM_CORE.balanceOf(actor);
        vm.prank(actor);
        try vault.withdraw(assetsIn, actor, actor) {
            uint256 burned = balanceBefore - ALM_CORE.balanceOf(actor);
            (ghostCheckpoints, ghostSharesBurned) = (ghostCheckpoints + 1, ghostSharesBurned + burned);
            ghostSyncMintTrips++;
            if (burned < shares) ghostRoundTripGains++;
        } catch (bytes memory reason) {
            _recordRevert(this.syncMintWithdraw.selector, reason);
        }
        _settleWatch(actor);
    }

    function coreMintBurn(uint256 actorSeed, uint256 shares)
        external
        countCall(this.coreMintBurn.selector)
        advanceBlock
    {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(ALM_CORE.pool_(), address(this));
        uint256 ceiling = CORE_HANDLER.boundByTickHeadroom(snapshot, IALMCore(address(ALM_CORE)).maxMint(actor));
        if (ceiling == 0) return;
        shares = bound(shares, 1, ceiling);
        (uint160 sqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        (uint256 paid0, uint256 paid1,) = snapshot.getMintAmounts(sqrtPriceX96, shares, true);
        ERC20Mock token0 = _fund(actor, ALM_CORE.token0(), address(ALM_CORE), paid0);
        ERC20Mock token1 = _fund(actor, ALM_CORE.token1(), address(ALM_CORE), paid1);
        _watch();

        vm.prank(actor);
        try ALM_CORE.mint(shares, actor) returns (uint256 amount0, uint256 amount1) {
            (paid0, paid1) = (amount0, amount1);
        } catch (bytes memory reason) {
            _recordRevert(this.coreMintBurn.selector, reason);
            return _settleWatch(actor);
        }
        (ghostCheckpoints, ghostSharesMinted) = (ghostCheckpoints + 1, ghostSharesMinted + shares);

        (uint256 before0, uint256 before1) = (token0.balanceOf(actor), token1.balanceOf(actor));
        vm.prank(actor);
        try ALM_CORE.burn(shares, actor, actor) {
            (ghostCheckpoints, ghostSharesBurned) = (ghostCheckpoints + 1, ghostSharesBurned + shares);
            ghostCoreTrips++;
            if (token0.balanceOf(actor) - before0 > paid0 || token1.balanceOf(actor) - before1 > paid1) {
                ghostRoundTripGains++;
            }
        } catch (bytes memory reason) {
            _recordRevert(this.coreMintBurn.selector, reason);
        }
        _settleWatch(actor);
    }

    function asyncCycle(uint256 actorSeed, uint256 assets, bool isToken0)
        external
        countCall(this.asyncCycle.selector)
        advanceBlock
    {
        address actor = CORE_HANDLER.actorAt(actorSeed);
        ALMVaultAsync vault = isToken0 ? ASYNC_VAULT0 : ASYNC_VAULT1;
        if (!_fresh(actor, address(vault))) return;
        {
            uint256 ceiling = CORE_HANDLER.requestAssetsFor(IALMCore(address(ALM_CORE)).maxMint(actor), isToken0);
            if (ceiling == 0) return;
            uint256 floor = CORE_HANDLER.requestAssetsFor(2, isToken0) + 1;
            assets = bound(assets, FixedPointMathLib.min(floor, ceiling), ceiling);
        }
        ERC20Mock asset = _fund(actor, vault.asset(), address(vault), assets);
        (uint160 trustedSqrtPriceX96,,,,,) = IMetadexCLPool(ALM_CORE.pool_()).slot0();
        _watch();
        CORE_HANDLER.noteMove(CORE_HANDLER.MOVE_ANY());

        vm.prank(actor);
        try vault.requestDeposit(assets, actor, actor) { }
        catch (bytes memory reason) {
            _recordRevert(this.asyncCycle.selector, reason);
            return _settleWatch(actor);
        }
        ghostCheckpoints++;
        uint256 escrowedBefore = ALM_CORE.balanceOf(address(ALM_CORE));
        if (!_clear(isToken0, true, actor, trustedSqrtPriceX96)) return _settleWatch(actor);
        ghostSharesMinted += ALM_CORE.balanceOf(address(ALM_CORE)) - escrowedBefore;

        uint256 shares;
        uint256 claimable = vault.maxDeposit(actor);
        vm.prank(actor);
        try vault.deposit(claimable, actor, actor) returns (uint256 claimed) {
            (ghostCheckpoints, shares) = (ghostCheckpoints + 1, claimed);
        } catch (bytes memory reason) {
            _recordRevert(this.asyncCycle.selector, reason);
            return _settleWatch(actor);
        }
        if (shares == 0) return _settleWatch(actor);

        vm.prank(actor);
        try vault.requestRedeem(shares, actor, actor) { }
        catch (bytes memory reason) {
            _recordRevert(this.asyncCycle.selector, reason);
            return _settleWatch(actor);
        }
        ghostCheckpoints++;
        if (!_clear(isToken0, false, actor, trustedSqrtPriceX96)) return _settleWatch(actor);
        ghostSharesBurned += shares;

        uint256 assetsBefore = asset.balanceOf(actor);
        vm.prank(actor);
        try vault.redeem(shares, actor, actor) {
            ghostCheckpoints++;
            ghostAsyncTrips++;
            if (asset.balanceOf(actor) - assetsBefore > assets) ghostRoundTripGains++;
        } catch (bytes memory reason) {
            _recordRevert(this.asyncCycle.selector, reason);
        }
        _settleWatch(actor);
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _fresh(address actor, address vault) internal view returns (bool fresh) {
        (uint256 claimableAssets, uint256 claimableShares) =
            IALMCore(address(ALM_CORE)).getClaimableDeposit(vault, actor);
        (uint256 claimableRedeemAssets, uint256 claimableRedeemShares) =
            IALMCore(address(ALM_CORE)).getClaimableRedeem(vault, actor);
        fresh = ALM_CORE.depositRecord(vault, actor).amountIn == 0 && ALM_CORE.redeemRecord(vault, actor).amountIn == 0
            && claimableAssets + claimableShares + claimableRedeemAssets + claimableRedeemShares == 0
            && IALMCore(address(ALM_CORE)).maxMint(actor) > 0;
    }

    function _clear(bool isToken0, bool isDeposit, address actor, uint160 trustedSqrtPriceX96)
        internal
        returns (bool cleared)
    {
        uint256 next = ALM_CORE.lastPlanAt_() + ALM_CORE.minPlanInterval_();
        uint256 timestamp = vm.getBlockTimestamp();
        if (timestamp < next) {
            vm.roll(vm.getBlockNumber() + (next - timestamp + BLOCK_TIME - 1) / BLOCK_TIME);
            vm.warp(next);
        }
        Plan.Steps memory plan = Plan.init().clearRequests(isToken0, isDeposit, Plan.one(actor)).settleRequests();
        vm.recordLogs();
        vm.prank(KEEPER);
        try ALM_CORE.execute(plan.commands, plan.inputs, trustedSqrtPriceX96) {
            ghostCheckpoints++;
            cleared = true;
        } catch (bytes memory reason) {
            _recordRevert(this.asyncCycle.selector, reason);
        }
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        if (cleared) CORE_HANDLER.noteSettlements(logs);
    }

    function _fund(address actor, address vault, uint256 assets) internal returns (ERC20Mock asset) {
        asset = _fund(actor, ALMVaultSync(vault).asset(), vault, assets);
    }

    function _fund(address actor, address token, address spender, uint256 amount) internal returns (ERC20Mock asset) {
        asset = ERC20Mock(token);
        asset.mint(actor, amount);
        vm.prank(actor);
        asset.approve(spender, type(uint256).max);
    }

    function _watch() internal {
        CORE_HANDLER.trackFairShares();
        CORE_HANDLER.watchPending();
    }

    function _settleWatch(address actor) internal {
        CORE_HANDLER.countPendingMoves(actor, actor);
    }

    function _afterAction() internal override {
        CORE_HANDLER.checkMonotone();
    }
}
