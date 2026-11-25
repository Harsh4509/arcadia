/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreHandler } from "./handlers/ALMCoreHandler.sol";
import { ALMCoreView } from "../../src/periphery/ALMCoreView.sol";
import { ALMKeeperExtension } from "../../src/core/ALMKeeperExtension.sol";
import { ALMVaultAsync } from "../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSyncHandler } from "./handlers/ALMVaultSyncHandler.sol";
import { ConfigLib } from "../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../utils/Constants.sol";
import { DonorHandler } from "./handlers/DonorHandler.sol";
import { Epoch, Record } from "../../src/core/types/State.sol";
import { ERC20Mock } from "../utils/mocks/ERC20Mock.sol";
import { ERC7540Operator } from "../../src/vaults/abstracts/tokens/ERC7540Operator.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { GaugeHandler } from "./handlers/GaugeHandler.sol";
import { GovernanceHandler } from "./handlers/GovernanceHandler.sol";
import { ICLGauge } from "../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { IERC721 } from "@forge-std/interfaces/IERC721.sol";
import { ICLGaugeFactory } from "../utils/fixtures/metadex/interfaces/ICLGaugeFactory.sol";
import { ILeafVoter } from "../utils/fixtures/metadex/interfaces/ILeafVoter.sol";
import { IMetadexCLPool } from "../../src/interfaces/IMetadexCLPool.sol";
import { INonfungiblePositionManager } from "../utils/fixtures/metadex/interfaces/INonfungiblePositionManager.sol";
import { Invariant_Test } from "./Invariant.t.sol";
import { KeeperHandler } from "./handlers/KeeperHandler.sol";
import { PoolHandler } from "./handlers/PoolHandler.sol";
import { Range } from "../../src/core/types/Range.sol";
import { RangesLib } from "../../src/core/libraries/state/RangesLib.sol";
import { RoundTripHandler } from "./handlers/RoundTripHandler.sol";
import { ShareLib } from "../../src/core/libraries/state/ShareLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Vaults } from "../../src/core/types/Vaults.sol";

/**
 * @notice Invariant tests for contract "ALMCore".
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local, unsafe-typecast, unused-return)
contract ALMCore_Invariant_Test is Invariant_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The positions the donor holds to send the core.
    uint256 internal constant DONATED_TOKEN_IDS = 4;

    // The per user cap, twice the seed.
    uint256 internal constant PER_USER_CAP = 2 * INITIAL_SUPPLY;

    // The total cap, four times the seed.
    uint256 internal constant TOTAL_CAP = 4 * INITIAL_SUPPLY;

    uint256 internal constant TRUSTED_DEVIATION = 1e16;

    // The least time between two plans, two blocks of BaseHandler.BLOCK_TIME.
    uint32 internal constant MIN_PLAN_INTERVAL = 4;

    uint16 internal constant MAX_SHORTFALL_BPS = 100;
    uint16 internal constant MAX_SWAP_COST_BPS = 100;

    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    // The fuzzed inputs a probe drives the handlers with.
    struct ProbeInputs {
        uint256 amount0;
        uint256 amount1;
        uint256 amountReward;
        uint256 minStakeBlocks;
        uint256 penaltyRate;
        address referral;
        uint256 share;
        uint256 status;
        uint256 emissionsPerVP;
        uint256 blocks;
        uint256 shares;
        uint256 assets;
        uint256 trustedSeed;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMCoreHandler internal handler;
    DonorHandler internal donorHandler;
    GaugeHandler internal gaugeHandler;
    KeeperHandler internal keeperHandler;
    GovernanceHandler internal governanceHandler;
    ALMVaultSyncHandler internal vaultHandler;
    PoolHandler internal poolHandler;
    RoundTripHandler internal roundTripHandler;
    ALMCoreView internal lens;
    address internal syncVault0;
    address internal syncVault1;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(Invariant_Test) {
        Invariant_Test.setUp();
        setInvariantState();
        addEmissionsToGaugeCL(pool, gauge, MAX_BASE_RATE / 2);
        closePenaltyWindow(gauge);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);

        vm.startPrank(factory);
        almCore.setPlanLimits(MAX_SHORTFALL_BPS, MAX_SWAP_COST_BPS, MIN_PLAN_INTERVAL);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, Constants.WIDE_DEVIATION, TRUSTED_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        almCore.setPerUserCap(PER_USER_CAP);
        almCore.lowerTotalCap(TOTAL_CAP);
        vm.stopPrank();

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("actorA");
        actors[1] = makeAddr("actorB");
        actors[2] = makeAddr("actorC");
        Vaults memory vaults_ = deployer.getVaults(address(almCore));
        (syncVault0, syncVault1) = (vaults_.syncVault0, vaults_.syncVault1);
        address[] memory vaults = new address[](4);
        (vaults[0], vaults[1], vaults[2], vaults[3]) = (syncVault0, syncVault1, asyncVault0, asyncVault1);
        handler = new ALMCoreHandler(
            almCore,
            ERC20Mock(address(token0)),
            ERC20Mock(address(token1)),
            actors,
            vaults,
            factory,
            address(this),
            users.steward,
            tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())
        );

        governanceHandler = new GovernanceHandler(almCore, handler, factory, users.steward);
        vaultHandler = new ALMVaultSyncHandler(almCore, handler, syncVault0, syncVault1, POSITION_MANAGER);
        roundTripHandler = new RoundTripHandler(almCore, handler, users.keeper, syncVault0, syncVault1);
        poolHandler = new PoolHandler(
            almCore,
            handler,
            pool,
            SWAP_ROUTER,
            makeAddr("trader"),
            TickMath.getSqrtPriceAtTick(-bandTick(pool.tickSpacing())) * 1e3,
            Constants.BOUND_SQRT_PRICE_UPPER / 1e3
        );
        lens = new ALMCoreView(factory);

        gaugeHandler = new GaugeHandler(
            almCore,
            handler,
            clGaugeFactory,
            ILeafVoter(address(leafVoter)),
            address(gauge),
            address(this),
            metadexConfigAdmin,
            pool,
            messageOrchestrator,
            VOTING_POWER,
            MAX_BASE_RATE
        );

        donorHandler = new DonorHandler(
            almCore,
            handler,
            POSITION_MANAGER,
            ERC20Mock(address(token0)),
            ERC20Mock(address(token1)),
            almCore.REWARD_TOKEN_()
        );
        for (uint256 i; i < DONATED_TOKEN_IDS; ++i) {
            (uint256 tokenId,) = mintPositionFor(
                pool,
                users.liquidityProvider,
                address(donorHandler),
                -pool.tickSpacing(),
                pool.tickSpacing(),
                Constants.MIN_FUZZED_LIQUIDITY
            );
            donorHandler.stageTokenId(tokenId);
        }

        address[] memory watched = new address[](8);
        (watched[0], watched[1], watched[2]) = (actors[0], actors[1], actors[2]);
        (watched[3], watched[4], watched[5], watched[6], watched[7]) =
        (users.keeper, users.steward, almCore.feeRecipient_(), makeAddr("trader"), address(donorHandler));
        keeperHandler = new KeeperHandler(
            almCore,
            handler,
            IMetadexCLPool(address(pool)),
            users.keeper,
            pool.tickSpacing(),
            address(SWAP_ROUTER),
            watched
        );
        handler.checkMonotone();

        targetContract(address(handler));
        targetContract(address(keeperHandler));
        targetContract(address(gaugeHandler));
        targetContract(address(donorHandler));
        targetContract(address(governanceHandler));
        targetContract(address(vaultHandler));
        targetContract(address(poolHandler));
        targetContract(address(roundTripHandler));

        bytes4[] memory hooks = new bytes4[](10);
        hooks[0] = ALMCoreHandler.watchPending.selector;
        hooks[1] = ALMCoreHandler.countPendingMoves.selector;
        hooks[2] = ALMCoreHandler.trackFairShares.selector;
        hooks[3] = ALMCoreHandler.earnedWithoutPenalty.selector;
        hooks[4] = ALMCoreHandler.hiddenEmissions.selector;
        hooks[5] = ALMCoreHandler.rebaseFairShares.selector;
        hooks[6] = ALMCoreHandler.countCapBreach.selector;
        hooks[7] = ALMCoreHandler.checkMonotone.selector;
        hooks[8] = ALMCoreHandler.noteMove.selector;
        hooks[9] = ALMCoreHandler.noteSettlements.selector;
        excludeSelector(FuzzSelector({ addr: address(handler), selectors: hooks }));

        bytes4[] memory staging = new bytes4[](1);
        staging[0] = DonorHandler.stageTokenId.selector;
        excludeSelector(FuzzSelector({ addr: address(donorHandler), selectors: staging }));
    }

    /* //////////////////////////////////////////////////////////////
                                 PROBES
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_probe_EveryGaugeAndDonorPathRuns(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: Every donor path and every gauge governance move runs once.
        donorHandler.donateToken0(inputs.amount0);
        donorHandler.donateToken1(inputs.amount1);
        donorHandler.donateRewardToken(inputs.amountReward);
        donorHandler.donateTokenId();
        gaugeHandler.setPenaltyConfig(inputs.minStakeBlocks, inputs.penaltyRate);
        gaugeHandler.setMinStakeBlocks(inputs.minStakeBlocks);
        gaugeHandler.setReferralConfig(inputs.referral, inputs.share);
        gaugeHandler.setChainStatus(inputs.status);
        gaugeHandler.accrueEmissions(inputs.emissionsPerVP);
        gaugeHandler.advanceBlocks(inputs.blocks);

        // Then: Every donation landed.
        assertGt(donorHandler.ghostDonated0(), 0);
        assertGt(donorHandler.ghostDonated1(), 0);
        assertGt(donorHandler.ghostDonatedReward(), 0);
        assertEq(donorHandler.ghostDonatedTokenIds(), 1);

        // And: Every governance move was hit, the three factory moves without a revert.
        assertEq(gaugeHandler.calls(gaugeHandler.setPenaltyConfig.selector), 1);
        assertEq(gaugeHandler.reverts(gaugeHandler.setPenaltyConfig.selector), 0);
        assertEq(gaugeHandler.reverts(gaugeHandler.setMinStakeBlocks.selector), 0);
        assertEq(gaugeHandler.reverts(gaugeHandler.setReferralConfig.selector), 0);
        assertEq(gaugeHandler.calls(gaugeHandler.setChainStatus.selector), 1);

        // And: Emissions accrued and blocks advanced.
        assertEq(gaugeHandler.ghostEmissionRounds(), 1);
        assertEq(gaugeHandler.calls(gaugeHandler.advanceBlocks.selector), 1);

        // And: The balances still cover what the core accounts.
        invariant_token0BalanceEqualsBufferFeesEscrowAndUnskimmedDonations();
        invariant_token1BalanceEqualsBufferFeesEscrowAndUnskimmedDonations();
        invariant_backedRewardPaidNeverExceedsWhatWasClaimed();
    }

    function testFuzz_Success_probe_EverySupplyGhostMoves(ProbeInputs memory inputs) public {
        // Given: A first plan that stores the exchange rate for requests.
        keeperHandler.collect(0);
        gaugeHandler.advanceBlocks(inputs.blocks);

        // And: A deposit worth two shares to the per user cap at the exchange rate.
        uint256 assets;
        {
            (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
            uint256 upper = FixedPointMathLib.max(sqrtPriceX96(pool), lastSqrtPrice);
            uint256 floor =
                (uint256(2) << 128).divUp(supplyPerValueX128).fullMulDivUp(1 << 96, upper).fullMulDivUp(1 << 96, upper);
            uint256 ceiling = PER_USER_CAP.fullMulDiv(1 << 128, supplyPerValueX128)
                .fullMulDiv(1 << 96, upper)
                .fullMulDiv(1 << 96, upper);
            assets = bound(inputs.assets, floor, FixedPointMathLib.min(ceiling, INITIAL_SUPPLY));
        }

        // And: A mint within the first actor's cap room.
        inputs.shares = bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)));

        // When: Mints, a burn and a redeem request, and both requests settle.
        handler.mint(0, inputs.shares);
        handler.burn(0, 0, 0, inputs.shares, 0);
        handler.mint(2, inputs.shares);
        handler.requestDeposit(1, 1, 1, assets, true);
        keeperHandler.clearAllDeposits(true, inputs.trustedSeed);
        gaugeHandler.advanceBlocks(inputs.blocks);
        handler.requestRedeem(2, 2, 2, 1, true, false);
        keeperHandler.clearAllRedeems(true, inputs.trustedSeed);

        // Then: Every ghost the supply invariant sums moved.
        assertGt(handler.ghostSharesMinted(), 0);
        assertGt(handler.ghostSharesBurned(), 0);
        assertGt(keeperHandler.ghostSharesSettledIn(), 0);
        assertGt(keeperHandler.ghostSharesSettledOut(), 0);

        // And: Each plan was checked against the loss bound.
        assertEq(keeperHandler.ghostPlansExecuted(), 3);
        invariant_supplyChangesOnlyThroughMintAndWithdraw();
        invariant_noPlanLosesMoreThanMaxShortfallPerShareAtTheTrustedPrice();
    }

    function testFuzz_Success_probe_EveryRewardGhostMoves(ProbeInputs memory inputs) public {
        // Given: A mint three actors' cap rooms take, and two actors holding aLP.
        inputs.shares = bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)) / 3);
        handler.mint(0, inputs.shares);
        handler.mint(1, inputs.shares);
        gaugeHandler.accrueEmissions(bound(inputs.emissionsPerVP, MAX_BASE_RATE / 2, MAX_BASE_RATE));
        gaugeHandler.advanceBlocks(inputs.blocks);

        // When: The first actor's credit is stored, a third mints, the first claims.
        handler.transfer(0, 1, 0, inputs.shares, false);
        handler.mint(2, inputs.shares);
        handler.claimEmissions(0, inputs.blocks);

        // Then: The accumulator moved and a bystander's credit was watched.
        assertGt(almCore.rewardPerShare_(), 0);
        assertGt(handler.ghostPendingWatched(), 0);

        // And: Reward was paid out.
        assertGt(handler.ghostRewardPaid(), 0);
        invariant_creditedRewardsNeverExceedTheHighWaterPlusThePreCredit();
        invariant_oneHoldersActionNeverMovesAnothersCreditedReward();
    }

    function testFuzz_Success_probe_EmergencyUnstakeForfeitsTheToken(ProbeInputs memory inputs) public {
        // Given: An actor holding aLP, and staked emissions credited by a transfer.
        inputs.shares = bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)));
        handler.mint(0, inputs.shares);
        gaugeHandler.accrueEmissions(bound(inputs.emissionsPerVP, MAX_BASE_RATE / 2, MAX_BASE_RATE));
        gaugeHandler.advanceBlocks(inputs.blocks);
        handler.transfer(0, 1, 0, inputs.shares, false);

        // When: The keeper takes the staked side out by emergency withdraw.
        keeperHandler.emergencyUnstake(0);

        // Then: The staked side left and its unclaimed emissions count as forfeited.
        assertEq(almCore.getRange(0).stakedTokenId, 0);
        assertGt(keeperHandler.ghostForfeited(), 0);

        // And: The deficit it left is within the forfeit.
        (,, uint256 total) = almCore.getRewardTotals();
        uint256 highWater = almCore.getRewardHighWater();
        assertGt(highWater, total);
        assertLe(highWater - total, keeperHandler.ghostForfeited());
        invariant_creditedRewardsNeverExceedTheHighWaterPlusThePreCredit();
        invariant_everyRangeHoldsOneUnstakedPositionAndAtMostOneSibling();
        invariant_noPlanLosesMoreThanMaxShortfallPerShareAtTheTrustedPrice();
    }

    function testFuzz_Success_probe_EveryForfeitAndGovernanceGhostMoves(ProbeInputs memory inputs) public {
        // Given: A full penalty window that holds the staked range throughout.
        inputs.minStakeBlocks = bound(inputs.minStakeBlocks, 64, gaugeHandler.MAX_MIN_STAKE_BLOCKS());
        gaugeHandler.setPenaltyConfig(inputs.minStakeBlocks, clGaugeFactory.MAX_PIPS());

        // And: An actor holding aLP, and emissions the window hides.
        inputs.shares = bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)));
        handler.mint(0, inputs.shares);
        inputs.emissionsPerVP = bound(inputs.emissionsPerVP, MAX_BASE_RATE / 2, MAX_BASE_RATE);
        gaugeHandler.accrueEmissions(inputs.emissionsPerVP);

        // When: The actor burns in the window, then the keeper unstakes, penalised.
        handler.burn(0, 0, 0, inputs.shares, 0);
        gaugeHandler.accrueEmissions(inputs.emissionsPerVP);
        keeperHandler.decreaseStakedAcceptingPenalty(0, uint128(inputs.amount0));

        // And: A fee raise fails in the window, passes after it, the referral moves.
        gaugeHandler.accrueEmissions(inputs.emissionsPerVP);
        handler.setProtocolFees(uint16(almCore.MAX_FEE_BPS_()), uint16(inputs.share), 0);
        assertEq(handler.ghostFeeRaises(), 0);
        vm.roll(vm.getBlockNumber() + inputs.minStakeBlocks);
        handler.setProtocolFees(uint16(almCore.MAX_FEE_BPS_()), uint16(inputs.share), 0);
        gaugeHandler.setReferralConfig(inputs.referral, inputs.share);

        // Then: Both penalised exits counted their forfeit.
        assertGt(handler.ghostForfeited(), 0);
        assertGt(keeperHandler.ghostForfeited(), 0);

        // And: The fee raise and both gauge moves were counted.
        assertEq(handler.ghostFeeRaises(), 1);
        assertEq(gaugeHandler.ghostGaugeConfigMoves(), 2);
        assertGt(gaugeHandler.ghostGaugeConfigLoss(), 0);
        invariant_rewardDeficitIsBoundedByForfeitsAndGovernanceMoves();
        invariant_creditedRewardsNeverExceedTheHighWaterPlusThePreCredit();
        invariant_preCreditEqualsTheHiddenEmissionsAtTheLastCheckpoint();
        invariant_burnsNeverRevertOnTheWindowLogic();
    }

    function testFuzz_Success_probe_BothCapsBind(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: Two actors mint to their caps and past them within the total room.
        handler.mint(0, INITIAL_SUPPLY);
        handler.mint(0, INITIAL_SUPPLY);
        handler.mint(0, bound(inputs.shares, 1, almCore.totalCap_() - almCore.totalSupply()));
        handler.mint(1, INITIAL_SUPPLY);
        handler.mint(1, bound(inputs.shares, 1, almCore.perUserCap_() - almCore.balanceOf(handler.actorAt(1))));

        // Then: The per user cap turned the third mint away and the total cap the last.
        assertEq(handler.revertsByReason(handler.mint.selector, ShareLib.PerUserCapExceeded.selector), 1);
        assertEq(handler.revertsByReason(handler.mint.selector, ShareLib.TotalCapExceeded.selector), 1);
        invariant_noSupplyIncreasePassesTheTotalCap();
    }

    function testFuzz_Success_probe_PenaltyWindowIsTried(ProbeInputs memory inputs) public {
        // Given: A live penalty window longer than the three blocks below.
        inputs.minStakeBlocks = bound(inputs.minStakeBlocks, 4, gaugeHandler.MAX_MIN_STAKE_BLOCKS());
        inputs.penaltyRate = bound(inputs.penaltyRate, 1, clGaugeFactory.MAX_PIPS());
        gaugeHandler.setPenaltyConfig(inputs.minStakeBlocks, inputs.penaltyRate);

        // When: The staked range is topped up, restarting its window, then unstaked.
        keeperHandler.stake(0, almCore.bufferAmount0(), almCore.bufferAmount1());
        gaugeHandler.advanceBlocks(1);
        keeperHandler.unstake(0, uint128(inputs.shares));

        // Then: The unstake was tried inside the window and turned away.
        assertGt(keeperHandler.ghostWindowAttempts(), 0);
        invariant_neverTouchesAPositionInsideItsPenaltyWindow();
    }

    function testFuzz_Success_probe_EveryGovernanceMoveBinds(ProbeInputs memory inputs) public {
        // Given: A first plan that stores the exchange rate for requests.
        keeperHandler.collect(0);
        gaugeHandler.advanceBlocks(inputs.blocks);

        // And: A mint within the total cap room.
        inputs.shares = bound(inputs.shares, 1, almCore.totalCap_() - almCore.totalSupply());

        // When: The core is paused, an actor mints and enters a vault, the keeper swaps.
        governanceHandler.pause(0);
        handler.mint(0, inputs.shares);
        vaultHandler.deposit(0, 0, inputs.assets, true, true, 0);
        keeperHandler.swap(true, inputs.amount0, 0, inputs.trustedSeed);

        // Then: The pause turned away every path that adds value.
        assertEq(handler.revertsByReason(handler.mint.selector, ALMKeeperExtension.Paused.selector), 1);
        assertEq(keeperHandler.revertsByReason(keeperHandler.swap.selector, ALMKeeperExtension.Paused.selector), 1);
        assertEq(vaultHandler.ghostSharesMinted(), 0);
        invariant_aPausedCoreAddsNoValue();

        // And: An unprivileged call is refused, an exempt actor mints past a zero cap.
        governanceHandler.callUnauthorized(1, inputs.share, inputs.amount1);
        assertEq(governanceHandler.reverts(governanceHandler.callUnauthorized.selector), 1);
        governanceHandler.unpause();
        governanceHandler.setCapExempt(2, true);
        governanceHandler.setCapWide(0, 0);
        handler.mint(2, inputs.shares);
        assertEq(handler.reverts(handler.mint.selector), 1);
        invariant_theExemptListIsNeverTurnedAwayByThePerUserCap();
    }

    function testFuzz_Success_probe_EveryKeeperPlanShapeRuns(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: The keeper runs a failing plan, a router swap and a rebalance.
        keeperHandler.failingPlan(0, inputs.amount0 % 2 == 0, inputs.amount1);
        keeperHandler.swapViaRouter(inputs.amount0 % 2 == 0, 1e6, inputs.trustedSeed);
        gaugeHandler.advanceBlocks(inputs.blocks);
        keeperHandler.rebalance(0, uint128(inputs.shares));

        // Then: The two-step plan and the router swap executed, the failed plan checked.
        assertEq(keeperHandler.ghostMultiStepPlans(), 1);
        assertEq(keeperHandler.ghostPlansReverted(), 1);
        assertEq(keeperHandler.ghostRouterSwaps(), 1);
        invariant_noPlanExecutesBelowItsMinimumOutput();
        invariant_noPlanLosesMoreThanMaxShortfallPerShareAtTheTrustedPrice();
    }

    function testFuzz_Success_probe_EveryVaultPathRuns(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: An actor mints half the supply in a vault, withdraws, redeems, deposits.
        vaultHandler.mint(0, 0, almCore.totalSupply() / 2, false, true, 0);
        uint256 balance = almCore.balanceOf(handler.actorAt(0));
        vaultHandler.withdraw(0, 0, 0, ALMVaultSync(syncVault0).previewRedeem(balance / 4), true, true, 1);
        vaultHandler.redeem(0, 0, 0, balance / 4, false, true, 1);
        vaultHandler.deposit(0, 0, inputs.assets, true, true, 1);

        // Then: Every vault path minted or burned shares, inside the band.
        assertGt(vaultHandler.ghostSharesMinted(), 0);
        assertGt(vaultHandler.ghostSharesBurned(), 0);
        invariant_supplyChangesOnlyThroughMintAndWithdraw();
        invariant_noSynchronousEntryOutsideTheBand();
        invariant_vaultsAndExtensionsHoldNoShares();
    }

    function testFuzz_Success_probe_AnEmissionFeeRaiseIsChecked(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: The emission fee is raised to the ceiling.
        handler.setProtocolFees(uint16(almCore.MAX_FEE_BPS_()), uint16(inputs.share), 0);

        // Then: The raise went through and was checked against what the gauge still owes.
        assertEq(handler.reverts(handler.setProtocolFees.selector), 0);
        assertEq(almCore.protocolEmissionFeeBps_(), Constants.MAX_FEE_BPS);
        invariant_anEmissionFeeRaiseLeavesNothingEarned();
    }

    function testFuzz_Success_probe_RandomPlansExecute(ProbeInputs memory inputs) public {
        // Given: A pending deposit and redeem in the token0 vault for every actor.
        for (uint256 i; i < handler.actorsLength(); ++i) {
            handler.requestDeposit(i, i, i, bound(inputs.assets, 1, INITIAL_SUPPLY), true);
            handler.mint(i, bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(i)) / 3));
            handler.requestRedeem(i, i, i, 1, true, false);
        }

        // When: Random plans of every length run, each after a fresh request.
        for (uint256 i; i < 2 * keeperHandler.PLAN_STEPS(); ++i) {
            handler.requestDeposit(i, i, i, bound(inputs.assets, 1, INITIAL_SUPPLY), true);
            handler.requestRedeem(i, i, i, 1, true, false);
            keeperHandler.plan(uint256(keccak256(abi.encode(inputs.trustedSeed, i))), i, inputs.trustedSeed, i % 2 == 0);
        }

        // Then: Random plans executed.
        assertGt(keeperHandler.ghostRandomPlans(), 0);
        invariant_noPlanLosesMoreThanMaxShortfallPerShareAtTheTrustedPrice();
        invariant_settledEpochsHoldWhatTheirPlanMovedThroughEscrow();
        invariant_settlementPaysNoFlowMoreThanItsProRataPart();
        invariant_plansKeepTheMinimumIntervalAndTheRangeCap();
    }

    function testFuzz_Success_probe_EveryShareSidePathRuns(ProbeInputs memory inputs) public {
        // Given: Two actors holding aLP and an operator approved for the first.
        inputs.shares = bound(inputs.shares, 2, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)) / 3);
        handler.mint(0, inputs.shares);
        handler.mint(1, inputs.shares);
        handler.setOperator(0, 2, 2, true);

        // And: A deposit worth two shares to a third of the first actor's cap room.
        uint256 assets;
        {
            (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
            uint256 upper = FixedPointMathLib.max(sqrtPriceX96(pool), lastSqrtPrice);
            uint256 floor =
                (uint256(2) << 128).divUp(supplyPerValueX128).fullMulDivUp(1 << 96, upper).fullMulDivUp(1 << 96, upper);
            uint256 ceiling = (coreViewLogic.maxMint(address(almCore), handler.actorAt(0)) / 3)
                .fullMulDiv(1 << 128, supplyPerValueX128)
                .fullMulDiv(1 << 96, upper)
                .fullMulDiv(1 << 96, upper);
            assets = bound(inputs.assets, floor, FixedPointMathLib.max(floor, ceiling));
        }

        // When: An operator requests for A, a spender moves and burns B's aLP.
        handler.requestDeposit(0, 0, 2, assets, true);
        handler.transfer(1, 0, 2, inputs.shares / 2, true);
        handler.burn(1, 2, 0, 1, 1);
        keeperHandler.clearAllDeposits(true, inputs.trustedSeed);

        // And: The operator claims the settled deposit by shares.
        handler.claimDepositRequest(0, 0, 2, inputs.shares, 1, true);

        // Then: Every share-side path went through.
        assertGt(handler.ghostOperatorCalls(), 0);
        assertEq(handler.ghostTransfersFrom(), 1);
        assertEq(handler.ghostSpenderBurns(), 1);
        assertEq(handler.ghostAsyncMints(), 1);
        invariant_claimsPayNoMoreThanTheirProRataPartAndGoThrough();
        invariant_noCapBalanceIncreasePassesThePerUserCap();
    }

    function testFuzz_Success_probe_EveryNewGovernanceMoveRuns(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: Every governance move runs once.
        governanceHandler.raiseTotalCap(inputs.amount0);
        governanceHandler.lowerPerUserCap(inputs.amount1);
        governanceHandler.setRangeCap(inputs.share);
        governanceHandler.setPlanLimits(inputs.amount0, inputs.amount1, inputs.blocks);
        governanceHandler.setDeviation(inputs.blocks, inputs.amount0, inputs.amount1, inputs.share);
        governanceHandler.pause(0);

        // Then: Every move went through and the pause reached the vaults.
        assertEq(governanceHandler.ghostCapRaises(), 1);
        assertEq(governanceHandler.ghostRangeCapMoves(), 1);
        assertEq(governanceHandler.ghostPlanLimitMoves(), 1);
        assertEq(governanceHandler.ghostDeviationMoves(), 1);
        assertTrue(ALMVaultSync(syncVault0).paused());
        invariant_configStaysWithinItsLimits();
        invariant_aPausedCoreAddsNoValue();
    }

    function testFuzz_Success_probe_EntriesAreTriedOutsideTheBandAndWhilePaused(ProbeInputs memory inputs) public {
        // Given: A narrow band around the TWAP and spot moved to twice its edge.
        governanceHandler.setDeviation(
            Constants.TWAP_WINDOW, TRUSTED_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        poolHandler.swapTo(type(uint256).max, type(uint256).max);

        // When: Entries are tried at any amount, then again while paused.
        vaultHandler.deposit(0, 0, inputs.assets, true, false, 0);
        vaultHandler.mint(1, 1, inputs.shares, false, false, 0);
        governanceHandler.pause(0);
        vaultHandler.deposit(0, 0, inputs.assets, false, false, 0);

        // Then: The attempts were made and none went through.
        assertGt(vaultHandler.ghostOutOfBandAttempts(), 0);
        assertGt(vaultHandler.ghostPausedAttempts(), 0);
        assertEq(vaultHandler.ghostSharesMinted(), 0);
        invariant_noSynchronousEntryOutsideTheBand();
        invariant_aPausedCoreAddsNoValue();
    }

    function testFuzz_Success_probe_DonationsSweepsAndPoolMovesRun(ProbeInputs memory inputs) public {
        // Given: An actor holding aLP.
        inputs.shares = bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)));
        handler.mint(0, inputs.shares);

        // When: aLP and liquidity are donated, a vault is swept and the pool moves.
        donorHandler.donateShares(0, inputs.shares);
        donorHandler.donateLiquidity(
            0, bound(inputs.amount0, 1, INITIAL_SUPPLY), bound(inputs.amount1, 1, INITIAL_SUPPLY)
        );
        vaultHandler.sweep(true);
        poolHandler.swapTo(inputs.trustedSeed, inputs.amount1);
        poolHandler.elapse(inputs.blocks);

        // Then: Every donation landed and the sweep left the vault empty.
        assertGt(donorHandler.ghostDonatedShares(), 0);
        assertGt(donorHandler.ghostDonatedLiquidity(), 0);
        assertEq(vaultHandler.ghostSweepLeftovers(), 0);
        invariant_coreBalanceIsTheControllersAndTheEpochsEscrow();
        invariant_rangeLiquidityMatchesItsPositions();
        invariant_token0BalanceEqualsBufferFeesEscrowAndUnskimmedDonations();
        invariant_token1BalanceEqualsBufferFeesEscrowAndUnskimmedDonations();
    }

    function testFuzz_Success_probe_EveryRoundTripRuns(ProbeInputs memory inputs) public {
        // Given: An actor holding aLP the withdraw leg may burn past its minted shares.
        uint256 room = coreViewLogic.maxMint(address(almCore), handler.actorAt(1));
        handler.mint(1, bound(inputs.shares, room / 4, room / 2));

        // And: Sync amounts of a quarter to a half of their max views.
        uint256 maxDeposit = ALMVaultSync(syncVault0).maxDeposit(handler.actorAt(0));
        uint256 maxMint = ALMVaultSync(syncVault1).maxMint(handler.actorAt(1));

        // And: An async deposit worth two shares to a third of actor A's cap room.
        uint256 assets;
        {
            (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
            uint256 lower = FixedPointMathLib.min(sqrtPriceX96(pool), lastSqrtPrice);
            uint256 floor = (uint256(2) << 128)
                .divUp(supplyPerValueX128)
                .fullMulDivUp(lastSqrtPrice, lower)
                .fullMulDivUp(lastSqrtPrice, lower);
            uint256 ceiling = (coreViewLogic.maxMint(address(almCore), handler.actorAt(0)) / 3)
                .fullMulDiv(1 << 128, supplyPerValueX128)
                .fullMulDiv(lower, lastSqrtPrice)
                .fullMulDiv(lower, lastSqrtPrice);
            assets = bound(inputs.amount0, floor, FixedPointMathLib.max(floor, ceiling));
        }

        // When: Every round trip runs once.
        roundTripHandler.syncDepositRedeem(0, bound(inputs.assets, maxDeposit / 4, maxDeposit / 2), true);
        roundTripHandler.syncMintWithdraw(1, bound(inputs.shares, maxMint / 4, maxMint / 2), false);
        roundTripHandler.coreMintBurn(2, inputs.shares);
        roundTripHandler.asyncCycle(0, assets, false);

        // Then: Every round trip completed without a gain.
        assertEq(roundTripHandler.ghostSyncDepositTrips(), 1);
        assertEq(roundTripHandler.ghostSyncMintTrips(), 1);
        assertEq(roundTripHandler.ghostCoreTrips(), 1);
        assertEq(roundTripHandler.ghostAsyncTrips(), 1);
        invariant_roundTripsExtractNoValue();
        invariant_supplyChangesOnlyThroughMintAndWithdraw();
    }

    function testFuzz_Success_probe_RefusalPathsAreTried(ProbeInputs memory inputs) public {
        // Given: The suite's staged core, its one range staked.

        // When: The keeper stakes and closes the staked range, then unstakes it.
        keeperHandler.stakeStakedRange(0, inputs.amount0, inputs.amount1);
        keeperHandler.closeRange(0);
        keeperHandler.emergencyUnstake(0);
        keeperHandler.unstakeUnstakedRange(0, uint128(inputs.shares));

        // And: Caps not lowered, paused clears, and empty and edge plans are tried.
        governanceHandler.lowerCapsToNoLower(inputs.amount0, inputs.amount1);
        governanceHandler.pause(0);
        keeperHandler.clearDepositsWhilePaused(true, inputs.share % 2 == 0, 0, inputs.trustedSeed);
        governanceHandler.unpause();
        keeperHandler.emptyPlan(inputs.trustedSeed);
        keeperHandler.planAtABandEdge(inputs.blocks, 0);

        // Then: Every refused step was tried and turned away for its own reason.
        assertEq(keeperHandler.ghostRefusalsTried(), 4);
        assertEq(keeperHandler.revertsByReason(keeperHandler.closeRange.selector, RangesLib.RangeStaked.selector), 1);
        assertEq(
            keeperHandler.revertsByReason(
                keeperHandler.unstakeUnstakedRange.selector, RangesLib.RangeNotStaked.selector
            ),
            1
        );
        assertEq(
            keeperHandler.revertsByReason(
                keeperHandler.clearDepositsWhilePaused.selector, ALMKeeperExtension.Paused.selector
            ),
            1
        );

        // And: Both cap calls were refused, and the empty plan ran.
        assertEq(governanceHandler.ghostNonLoweringTried(), 2);
        assertEq(governanceHandler.reverts(governanceHandler.lowerCapsToNoLower.selector), 2);
        assertEq(keeperHandler.reverts(keeperHandler.emptyPlan.selector), 0);
        invariant_refusedStepsRevertForTheirReason();
        invariant_lowerOnlyCapCallsNeverHoldOrRaise();
        invariant_anEmptyPlanRunsInsideBothBands();
        invariant_plansRunExactlyInsideBothTrustedBands();
        invariant_rangesMoveOnlyThroughTheirSteps();
    }

    function testFuzz_Success_probe_RequestStatesAndPayoutsAreChecked(ProbeInputs memory inputs) public {
        // Given: A first plan that stores the exchange rate for requests.
        keeperHandler.collect(0);
        gaugeHandler.advanceBlocks(inputs.blocks);

        // And: An actor holding aLP within a third of its cap room.
        inputs.shares = bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(0)) / 3);
        handler.mint(0, inputs.shares);

        // And: A deposit worth two shares to a third of the actor's cap room.
        uint256 assets;
        {
            (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
            uint256 upper = FixedPointMathLib.max(sqrtPriceX96(pool), lastSqrtPrice);
            uint256 floor =
                (uint256(2) << 128).divUp(supplyPerValueX128).fullMulDivUp(1 << 96, upper).fullMulDivUp(1 << 96, upper);
            uint256 ceiling = (coreViewLogic.maxMint(address(almCore), handler.actorAt(0)) / 3)
                .fullMulDiv(1 << 128, supplyPerValueX128)
                .fullMulDiv(1 << 96, upper)
                .fullMulDiv(1 << 96, upper);
            assets = bound(inputs.assets, floor, FixedPointMathLib.max(floor, ceiling));
        }

        // When: A stranger and the actor request, and a plan clears it.
        handler.requestDeposit(0, 0, 1, assets, true);
        handler.requestDeposit(0, 0, 0, assets, true);
        keeperHandler.clearAllDeposits(true, inputs.trustedSeed);

        // And: While paused the actor redeems and claims, fees and emissions are paid.
        governanceHandler.pause(0);
        handler.requestRedeem(0, 0, 0, 1, true, false);
        handler.claimDepositRequest(0, 0, 0, inputs.shares, 0, true);
        handler.payProtocolFees();
        handler.claimEmissions(0, inputs.blocks);
        governanceHandler.unpause();
        keeperHandler.swapViaRouter(true, 1e6, inputs.trustedSeed);

        // Then: The stranger was refused and the epoch settled.
        assertEq(handler.revertsByReason(handler.requestDeposit.selector, ERC7540Operator.Unauthorized.selector), 1);
        assertEq(handler.ghostEpochsSettled(), 1);

        // And: The paused request and claim went through, every payout was checked.
        assertEq(handler.reverts(handler.requestRedeem.selector), 0);
        assertEq(handler.reverts(handler.claimDepositRequest.selector), 0);
        assertEq(handler.ghostFeePayouts(), 1);
        assertEq(handler.ghostOwedClaimsChecked(), 1);
        assertEq(keeperHandler.ghostSwapsChecked(), 1);
        invariant_onlyControllersAndOperatorsMoveRequests();
        invariant_redeemRequestsCancelsAndClaimsStayOpenWhilePaused();
        invariant_requestsMoveOnlyAlongTheirStateMachine();
        invariant_everyClearedEpochSettlesOnceAndOnlyDrainsAfter();
        invariant_feePayoutsPayTheBookedFeesToTheRecipient();
        invariant_aClaimPaysTheRewardOwedBeforeIt();
        invariant_noPlanPaysAnAccountBeyondItsCancelledDeposits();
        invariant_everySwapStaysWithinTheMaxSwapCost();
    }

    function testFuzz_Success_probe_EveryUserActionSucceedsOnRawInputs(ProbeInputs memory inputs) public {
        // Given: A first plan that stores the exchange rate for requests.
        keeperHandler.collect(0);
        gaugeHandler.advanceBlocks(inputs.blocks);

        // When: An async round trip runs, and a deposit request is settled.
        roundTripHandler.asyncCycle(2, inputs.amount1, inputs.status % 2 == 1);
        handler.requestDeposit(1, 1, 1, inputs.assets, inputs.status % 2 == 0);
        keeperHandler.clearAllDeposits(inputs.status % 2 == 0, inputs.trustedSeed);

        // And: A third mints, earns emissions, claims them, burns and requests a redeem.
        handler.mint(0, inputs.shares);
        gaugeHandler.accrueEmissions(bound(inputs.emissionsPerVP, MAX_BASE_RATE / 2, MAX_BASE_RATE));
        gaugeHandler.advanceBlocks(inputs.blocks);
        handler.claimEmissions(0, inputs.blocks);
        handler.burn(0, 0, 0, inputs.amount0, inputs.penaltyRate);
        handler.requestRedeem(0, 0, 0, inputs.amount1, inputs.status % 2 == 1, false);

        // Then: Every action went through.
        assertEq(roundTripHandler.ghostAsyncTrips(), 1);
        assertEq(handler.reverts(handler.requestDeposit.selector), 0);
        assertEq(handler.reverts(handler.requestRedeem.selector), 0);
        assertGt(handler.ghostSharesMinted(), 0);
        assertGt(handler.ghostSharesBurned(), 0);
        assertGt(handler.ghostRewardPaid(), 0);

        // And: Every plan executed and settled its epochs.
        assertEq(keeperHandler.ghostPlansExecuted(), 2);
        assertEq(handler.ghostEpochsSettled(), 3);
        invariant_supplyChangesOnlyThroughMintAndWithdraw();
        invariant_rewardPayoutsStayWithinTheRewardBalance();
    }

    function testFuzz_Success_probe_SwapsAndSyncTripsSucceed(ProbeInputs memory inputs) public {
        // Given: An actor holding aLP the withdraw leg may burn past its minted shares.
        uint256 room = coreViewLogic.maxMint(address(almCore), handler.actorAt(1));
        handler.mint(1, bound(inputs.amount1, room / 4, room / 2));

        // And: Sync amounts of a quarter to a half of their max views.
        uint256 maxDeposit = ALMVaultSync(syncVault0).maxDeposit(handler.actorAt(0));
        uint256 maxMint = ALMVaultSync(syncVault1).maxMint(handler.actorAt(1));

        // When: The keeper swaps within the price step and cost band, and both trips run.
        (uint256 floor, uint256 ceiling) = swapBounds(true, almCore.bufferAmount0());
        keeperHandler.swap(true, bound(inputs.amount0, floor, ceiling), 0, inputs.trustedSeed);
        roundTripHandler.syncDepositRedeem(0, bound(inputs.assets, maxDeposit / 4, maxDeposit / 2), true);
        roundTripHandler.syncMintWithdraw(1, bound(inputs.shares, maxMint / 4, maxMint / 2), false);

        // Then: The plan made exactly one swap and both trips completed.
        assertEq(keeperHandler.ghostSwapsExecuted(), 1);
        assertEq(roundTripHandler.ghostSyncDepositTrips(), 1);
        assertEq(roundTripHandler.ghostSyncMintTrips(), 1);
        invariant_noPlanMakesMoreThanOneSwap();
        invariant_syncFlowsKeepWhatARemainingShareIsOwedInKind();
        invariant_vaultsAndExtensionsHoldNoPoolTokenButEntryLeftovers();
    }

    function testFuzz_Success_probe_UnauthorizedMovesAndSettledCancelsAreRefused(ProbeInputs memory inputs) public {
        // Given: An actor holding aLP, and a settled, unclaimed deposit of another.
        handler.mint(1, bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(1)) / 3));
        keeperHandler.collect(0);
        uint256 ceiling = handler.maxRequestAssets(handler.actorAt(0), true);
        handler.requestDeposit(0, 0, 0, bound(inputs.assets, handler.requestAssetsFor(2, true) + 1, ceiling), true);
        keeperHandler.clearAllDeposits(true, inputs.trustedSeed);

        // When: A stranger moves the holder's aLP every way, and both cancel.
        for (uint256 kind; kind < 5; ++kind) {
            handler.moveUnauthorized(1, 2, 2, inputs.amount0, kind);
        }
        handler.cancel(0, 0, 0, false, true);
        handler.cancel(0, 0, 2, false, true);

        // And: The depositor claims an exact share amount.
        handler.claimDepositRequest(0, 0, 0, inputs.amount1, 3, true);

        // Then: Every move and cancel was tried and refused, and the claim went through.
        assertEq(handler.ghostUnauthorizedMovesTried(), 5);
        assertEq(handler.reverts(handler.moveUnauthorized.selector), 5);
        assertEq(handler.ghostSettledCancelsTried(), 2);
        assertEq(handler.reverts(handler.cancel.selector), 2);
        assertEq(handler.ghostAsyncMints(), 1);
        invariant_noUnauthorizedCallerMovesAnothersShares();
        invariant_aSettledRequestIsNeverCancelled();
        invariant_claimsPayNoMoreThanTheirProRataPartAndGoThrough();
    }

    function testFuzz_Success_probe_OrderSwapCountAndLimitRefusalsAreTried(ProbeInputs memory inputs) public {
        // Given: A pending deposit, an actor holding aLP, and a sync deposit amount.
        handler.requestDeposit(0, 0, 0, inputs.assets, true);
        handler.mint(1, bound(inputs.shares, 1, coreViewLogic.maxMint(address(almCore), handler.actorAt(1)) / 3));
        uint256 maxDeposit = ALMVaultSync(syncVault0).maxDeposit(handler.actorAt(2));

        // When: The keeper builds before settling, and swaps twice.
        keeperHandler.buildWhileUnsettled(0, inputs.shares, inputs.status % 2 == 0, inputs.trustedSeed);
        (uint256 floor, uint256 ceiling) = swapBounds(true, almCore.bufferAmount0() / 2);
        keeperHandler.swapTwice(true, bound(inputs.amount0, floor, ceiling), inputs.share % 2 == 0);

        // And: Bounded sync calls are made with a limit one unit past their previews.
        vaultHandler.deposit(2, 2, bound(inputs.amount1, maxDeposit / 4, maxDeposit / 2), true, true, 2);
        vaultHandler.redeem(1, 1, 1, inputs.shares, true, true, 2);

        // Then: Each was refused for its own reason.
        assertEq(keeperHandler.ghostOrderRefusals(), 1);
        assertEq(keeperHandler.ghostTooManySwapsRefusals(), 1);
        assertEq(vaultHandler.ghostLimitRefusals(), 2);
        invariant_refusedStepsRevertForTheirReason();
        invariant_boundedSyncCallsKeepTheirLimits();
    }

    function testFuzz_Success_probe_WideGovernanceMovesRun(ProbeInputs memory inputs) public {
        // Given: The suite's staged core and handlers.

        // When: Plan limits and deviations are drawn over their whole ranges.
        governanceHandler.setPlanLimitsWide(inputs.amount0, inputs.amount1, inputs.blocks);
        governanceHandler.setDeviationWide(inputs.blocks, inputs.amount0, inputs.amount1, inputs.share);

        // Then: Both moves went through.
        assertEq(governanceHandler.ghostPlanLimitMoves(), 1);
        assertEq(governanceHandler.ghostDeviationMoves(), 1);
        invariant_configStaysWithinItsLimits();
        invariant_rangesStayWithinTheirCaps();
    }

    /* //////////////////////////////////////////////////////////////
                               INVARIANTS
    ////////////////////////////////////////////////////////////// */

    function invariant_token0BalanceEqualsBufferFeesEscrowAndUnskimmedDonations() public view virtual {
        uint256 accounted = almCore.bufferAmount0() + almCore.getProtocolFees0() + almCore.getEscrowed0();
        uint256 unskimmed = donorHandler.ghostDonated0() + vaultHandler.ghostSwept0() - handler.ghostSkimmed0()
            - vaultHandler.ghostSweepSkimmed0();

        assertEq(accounted + unskimmed, token0.balanceOf(address(almCore)));
    }

    function invariant_token1BalanceEqualsBufferFeesEscrowAndUnskimmedDonations() public view virtual {
        uint256 accounted = almCore.bufferAmount1() + almCore.getProtocolFees1() + almCore.getEscrowed1();
        uint256 unskimmed = donorHandler.ghostDonated1() + vaultHandler.ghostSwept1() - handler.ghostSkimmed1()
            - vaultHandler.ghostSweepSkimmed1();

        assertEq(accounted + unskimmed, token1.balanceOf(address(almCore)));
    }

    function invariant_rewardTokenCoversTheRewardBalance() public view {
        assertGe(ERC20Mock(rewardToken).balanceOf(address(almCore)), almCore.getLastRewardBalance());
    }

    function invariant_supplyChangesOnlyThroughMintAndWithdraw() public view {
        uint256 minted = handler.ghostSharesMinted() + keeperHandler.ghostSharesSettledIn()
            + vaultHandler.ghostSharesMinted() + roundTripHandler.ghostSharesMinted();
        uint256 burned = handler.ghostSharesBurned() + keeperHandler.ghostSharesSettledOut()
            + vaultHandler.ghostSharesBurned() + roundTripHandler.ghostSharesBurned();

        assertEq(almCore.totalSupply(), INITIAL_SUPPLY + minted - burned);
    }

    function invariant_supplyIsTheSumOfBalances() public view {
        uint256 sum = almCore.balanceOf(users.steward) + almCore.balanceOf(deadAddress)
            + almCore.balanceOf(address(almCore)) + almCore.balanceOf(syncVault0) + almCore.balanceOf(syncVault1)
            + almCore.balanceOf(asyncVault0) + almCore.balanceOf(asyncVault1)
            + almCore.balanceOf(almCore.KEEPER_EXTENSION_()) + almCore.balanceOf(almCore.ADMIN_EXTENSION_());
        for (uint256 i; i < handler.actorsLength(); ++i) {
            sum += almCore.balanceOf(handler.actorAt(i));
        }

        assertEq(sum, almCore.totalSupply());
    }

    function invariant_backedRewardPaidNeverExceedsWhatWasClaimed() public view {
        assertLe(handler.ghostBackedRewardPaid(), almCore.getClaimedCumulative());
    }

    function invariant_highWaterCoversWhatWasClaimed() public view {
        assertGe(almCore.getRewardHighWater(), almCore.getClaimedCumulative());
    }

    function invariant_noAccountIsPaidAheadOfTheAccumulator() public view {
        uint256 rewardPerShare = almCore.rewardPerShare_();
        for (uint256 i; i < handler.actorsLength() + 3; ++i) {
            assertLe(almCore.getRewardSnapshot(handler.holderAt(i)), rewardPerShare);
        }
        assertLe(almCore.getProtocolRewardSnapshot(), rewardPerShare);
    }

    function invariant_accumulatorsEpochIdsAndPlanTimesNeverFall() public view {
        assertEq(handler.ghostMonotoneBreaks(), 0);
        assertEq(keeperHandler.ghostEpochIdBreaches(), 0);
    }

    function invariant_noSupplyIncreasePassesTheTotalCap() public view {
        assertEq(handler.ghostTotalCapBreaches(), 0);
        assertEq(keeperHandler.ghostTotalCapBreaches(), 0);
        assertEq(vaultHandler.ghostTotalCapBreaches(), 0);
    }

    function invariant_noCapBalanceIncreasePassesThePerUserCap() public view {
        assertEq(handler.ghostUserCapBreaches(), 0);
    }

    function invariant_theExemptListIsNeverTurnedAwayByThePerUserCap() public view {
        assertEq(handler.ghostExemptRefusals(), 0);
    }

    function invariant_aPausedCoreAddsNoValue() public view {
        assertEq(handler.ghostPausedAccepts(), 0);
        assertEq(keeperHandler.ghostPausedAccepts(), 0);
        assertEq(vaultHandler.ghostPausedAccepts(), 0);
        for (uint256 i; i < handler.actorsLength(); ++i) {
            address actor = handler.actorAt(i);
            if (almCore.paused_()) assertEq(coreViewLogic.maxMint(address(almCore), actor), 0);
            assertFalse(vaultHandler.roomWhilePaused(actor));
        }
    }

    function invariant_unauthorizedCallsAreRefused() public view {
        assertEq(governanceHandler.ghostUnauthorizedAccepted(), 0);
    }

    function invariant_noPlanExecutesBelowItsMinimumOutput() public view {
        assertEq(keeperHandler.ghostBelowMinimumOutputs(), 0);
    }

    function invariant_stayersValuePerShareNeverFallsOnMintOrWithdraw() public view {
        assertEq(handler.ghostPerShareFalls(), 0);
    }

    function invariant_anEmissionFeeRaiseLeavesNothingEarned() public view {
        assertEq(handler.ghostRaisesLeavingEarned(), 0);
    }

    function invariant_noSynchronousEntryOutsideTheBand() public view {
        assertEq(vaultHandler.ghostOutOfBandEntries(), 0);
    }

    function invariant_vaultsAndExtensionsHoldNoShares() public view {
        assertEq(almCore.balanceOf(asyncVault0), 0);
        assertEq(almCore.balanceOf(asyncVault1), 0);
        assertEq(almCore.balanceOf(syncVault0), 0);
        assertEq(almCore.balanceOf(syncVault1), 0);
        assertEq(almCore.balanceOf(almCore.KEEPER_EXTENSION_()), 0);
        assertEq(almCore.balanceOf(almCore.ADMIN_EXTENSION_()), 0);
        for (uint256 i; i < 2; ++i) {
            address syncVault = i == 0 ? syncVault0 : syncVault1;
            assertEq(almCore.pendingShares_(syncVault) + almCore.claimableSharesOf_(syncVault), 0);
            assertEq(almCore.getPendingReward(syncVault), 0);
        }
    }

    function invariant_vaultsAndExtensionsHoldNoPoolTokenButEntryLeftovers() public view {
        address keeperExtension = almCore.KEEPER_EXTENSION_();
        address adminExtension = almCore.ADMIN_EXTENSION_();
        assertEq(token0.balanceOf(syncVault0), 0);
        assertEq(token1.balanceOf(syncVault1), 0);
        assertEq(token0.balanceOf(asyncVault0) + token1.balanceOf(asyncVault0), 0);
        assertEq(token0.balanceOf(asyncVault1) + token1.balanceOf(asyncVault1), 0);
        assertEq(token0.balanceOf(keeperExtension) + token1.balanceOf(keeperExtension), 0);
        assertEq(token0.balanceOf(adminExtension) + token1.balanceOf(adminExtension), 0);
    }

    function invariant_sweepsLeaveNothingInTheVault() public view {
        assertEq(vaultHandler.ghostSweepLeftovers(), 0);
    }

    function invariant_creditedRewardsNeverExceedTheHighWaterPlusThePreCredit() public view {
        (uint256 credited, uint256 accrued) = handler.creditedAndAccrued();

        assertLe(credited + accrued, almCore.getRewardHighWater() + almCore.getPreCredited());
    }

    function invariant_creditedRewardsCoverTheHighWaterLessRounding() public view {
        (uint256 credited, uint256 accrued) = handler.creditedAndAccrued();
        uint256 checkpoints = handler.ghostCheckpoints() + keeperHandler.ghostCheckpoints()
            + vaultHandler.ghostCheckpoints() + governanceHandler.ghostCheckpoints()
            + roundTripHandler.ghostCheckpoints() + donorHandler.ghostCheckpoints();
        uint256 rounding =
            checkpoints * (handler.ghostMaxSupply() / 1e18 + handler.actorsLength() + 2) + handler.actorsLength() + 3;

        assertGe(credited + accrued + rounding, almCore.getRewardHighWater() + almCore.getPreCredited());
    }

    function invariant_noPreCreditWithoutAnOpenWindow() public view {
        if (almCore.getWindowEnd() == 0) assertEq(almCore.getPreCredited(), 0);
    }

    function invariant_preCreditEqualsTheHiddenEmissionsAtTheLastCheckpoint() public {
        uint256 snapshot = vm.snapshotState();
        almCore.checkpoint_();

        uint256 windowEnd = almCore.getWindowEnd();
        if (windowEnd == 0) {
            assertEq(almCore.getPreCredited(), 0);
        } else {
            uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
            assertEq(
                almCore.getPreCredited(),
                hidden - hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_()
            );

            ICLGaugeFactory.PenaltyConfig memory config = clGaugeFactory.effectivePenaltyConfig(address(gauge));
            uint256 latestEnd;
            for (uint256 i; i < almCore.getRangesLength(); ++i) {
                uint256 tokenId = almCore.getRange(i).stakedTokenId;
                if (tokenId == 0) continue;
                uint256 end = gauge.depositBlock(tokenId) + config.minStakeBlocks;
                if (config.penaltyRate > 0 && vm.getBlockNumber() < end && end > latestEnd) latestEnd = end;
            }
            assertEq(windowEnd, latestEnd);
        }

        vm.revertToStateAndDelete(snapshot);
    }

    function invariant_rewardDeficitIsBoundedByForfeitsAndGovernanceMoves() public view {
        (,, uint256 total) = almCore.getRewardTotals();
        uint256 highWater = almCore.getRewardHighWater();
        if (highWater <= total) return;

        uint256 losses = handler.ghostForfeited() + keeperHandler.ghostForfeited() + vaultHandler.ghostForfeited()
            + gaugeHandler.ghostGaugeConfigLoss() + handler.ghostPreCreditDrops();
        assertLe(highWater - total, losses);
    }

    function invariant_noHolderEarnsMoreThanItsBlocks() public view {
        uint256 checkpoints = handler.ghostCheckpoints() + keeperHandler.ghostCheckpoints()
            + vaultHandler.ghostCheckpoints() + governanceHandler.ghostCheckpoints()
            + roundTripHandler.ghostCheckpoints() + donorHandler.ghostCheckpoints();
        for (uint256 i; i < handler.actorsLength(); ++i) {
            address actor = handler.actorAt(i);
            uint256 credited = almCore.getPendingReward(actor) + handler.ghostRewardPaidOf(actor);
            assertLe(credited, handler.ghostFairRewardOf(actor) + checkpoints);
        }
    }

    function invariant_burnsNeverRevertOnTheWindowLogic() public view {
        assertEq(handler.ghostUnexpectedBurnReverts(), 0);
    }

    function invariant_oneHoldersActionNeverMovesAnothersCreditedReward() public view {
        assertEq(handler.ghostPendingMoved(), 0);
    }

    function invariant_pendingEpochInputIsTheSumOfItsPendingRecords() public view {
        for (uint256 v; v < handler.asyncVaultsLength(); ++v) {
            address vault = handler.asyncVaultAt(v);
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            uint256 deposits;
            uint256 redeems;
            for (uint256 i; i < handler.actorsLength(); ++i) {
                Record memory deposit = almCore.depositRecord(vault, handler.actorAt(i));
                if (deposit.amountIn != 0 && deposit.epoch == pendingDepositEpoch) deposits += deposit.amountIn;
                Record memory redeem = almCore.redeemRecord(vault, handler.actorAt(i));
                if (redeem.amountIn != 0 && redeem.epoch == pendingRedeemEpoch) redeems += redeem.amountIn;
            }

            Epoch memory pendingDeposit = almCore.depositEpoch(vault, pendingDepositEpoch);
            assertEq(pendingDeposit.amountIn, deposits);
            assertEq(pendingDeposit.amountOut, 0);
            Epoch memory pendingRedeem = almCore.redeemEpoch(vault, pendingRedeemEpoch);
            assertEq(pendingRedeem.amountIn, redeems);
            assertEq(pendingRedeem.amountOut, 0);
        }
    }

    function invariant_settledEpochInputIsTheSumOfItsSettledRecords() public view {
        for (uint256 q; q < 2 * handler.asyncVaultsLength(); ++q) {
            address vault = handler.asyncVaultAt(q / 2);
            bool isDeposit = q % 2 == 0;
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(vault);
            uint256 pendingEpoch = isDeposit ? pendingDepositEpoch : pendingRedeemEpoch;
            uint256 lastEpoch =
                FixedPointMathLib.max(pendingEpoch, isDeposit ? lastClearedDepositEpoch : lastClearedRedeemEpoch);
            for (uint32 e; e <= lastEpoch; ++e) {
                if (e == pendingEpoch) continue;
                uint256 amountIn;
                for (uint256 i; i < handler.actorsLength(); ++i) {
                    Record memory record = isDeposit
                        ? almCore.depositRecord(vault, handler.actorAt(i))
                        : almCore.redeemRecord(vault, handler.actorAt(i));
                    if (record.amountIn != 0 && record.epoch == e) amountIn += record.amountIn;
                }
                Epoch memory settled = isDeposit ? almCore.depositEpoch(vault, e) : almCore.redeemEpoch(vault, e);
                assertEq(settled.amountIn, amountIn);
                if (settled.amountIn == 0) assertEq(settled.amountOut, 0);
            }
        }
    }

    function invariant_coreBalanceIsTheControllersAndTheEpochsEscrow() public view {
        uint256 escrowed = donorHandler.ghostDonatedShares();
        for (uint256 i; i < handler.actorsLength(); ++i) {
            escrowed += almCore.claimableSharesOf_(handler.actorAt(i));
        }
        for (uint256 v; v < handler.asyncVaultsLength(); ++v) {
            address vault = handler.asyncVaultAt(v);
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            (uint32 lastClearedDepositEpoch,) = almCore.lastClearedEpochs(vault);
            uint256 lastDepositEpoch = FixedPointMathLib.max(pendingDepositEpoch, lastClearedDepositEpoch);
            for (uint32 e; e <= lastDepositEpoch; ++e) {
                if (e != pendingDepositEpoch) escrowed += almCore.depositEpoch(vault, e).amountOut;
            }
            escrowed += almCore.redeemEpoch(vault, pendingRedeemEpoch).amountIn;
        }

        assertEq(almCore.balanceOf(address(almCore)), escrowed);
    }

    function invariant_controllerEscrowAndPendingSharesAreItsPilesAndRecords() public view {
        for (uint256 i; i < handler.actorsLength(); ++i) {
            address actor = handler.actorAt(i);
            uint256 piles = almCore.claimableDeposit(asyncVault0, actor).amountOut
                + almCore.claimableDeposit(asyncVault1, actor).amountOut;
            uint256 records = almCore.depositRecord(asyncVault0, actor).pendingShares
                + almCore.depositRecord(asyncVault1, actor).pendingShares
                + almCore.redeemRecord(asyncVault0, actor).amountIn + almCore.redeemRecord(asyncVault1, actor).amountIn;

            assertEq(almCore.claimableSharesOf_(actor), piles);
            assertEq(almCore.pendingShares_(actor), records);
        }
    }

    function invariant_asyncPendingViewsAreThePendingRecords() public view {
        for (uint256 v; v < handler.asyncVaultsLength(); ++v) {
            address vault = handler.asyncVaultAt(v);
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            for (uint256 i; i < handler.actorsLength(); ++i) {
                address actor = handler.actorAt(i);
                Record memory deposit = almCore.depositRecord(vault, actor);
                Record memory redeem = almCore.redeemRecord(vault, actor);

                assertEq(
                    ALMVaultAsync(vault).pendingDepositRequest(0, actor),
                    deposit.epoch == pendingDepositEpoch ? deposit.amountIn : 0
                );
                assertEq(
                    ALMVaultAsync(vault).pendingRedeemRequest(0, actor),
                    redeem.epoch == pendingRedeemEpoch ? redeem.amountIn : 0
                );
            }
        }
    }

    function invariant_tokenEscrowIsTheEpochsAndTheRedeemPiles() public view {
        for (uint256 v; v < handler.asyncVaultsLength(); ++v) {
            address vault = handler.asyncVaultAt(v);
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            uint256 owed = almCore.depositEpoch(vault, pendingDepositEpoch).amountIn;
            (, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(vault);
            uint256 lastRedeemEpoch = FixedPointMathLib.max(pendingRedeemEpoch, lastClearedRedeemEpoch);
            for (uint32 e; e <= lastRedeemEpoch; ++e) {
                if (e != pendingRedeemEpoch) owed += almCore.redeemEpoch(vault, e).amountOut;
            }
            for (uint256 i; i < handler.actorsLength(); ++i) {
                owed += almCore.claimableRedeem(vault, handler.actorAt(i)).amountOut;
            }

            assertEq(vault == asyncVault0 ? almCore.getEscrowed0() : almCore.getEscrowed1(), owed);
        }
    }

    function invariant_recordEpochsStayAtOrBelowTheHighestId() public view {
        for (uint256 v; v < handler.asyncVaultsLength(); ++v) {
            address vault = handler.asyncVaultAt(v);
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(vault);
            uint256 lastDepositEpoch = FixedPointMathLib.max(pendingDepositEpoch, lastClearedDepositEpoch);
            uint256 lastRedeemEpoch = FixedPointMathLib.max(pendingRedeemEpoch, lastClearedRedeemEpoch);
            for (uint256 i; i < handler.actorsLength(); ++i) {
                assertLe(almCore.depositRecord(vault, handler.actorAt(i)).epoch, lastDepositEpoch);
                assertLe(almCore.redeemRecord(vault, handler.actorAt(i)).epoch, lastRedeemEpoch);
            }
        }
    }

    function invariant_settleWithoutASwapNeverLowersTheStayersValuePerShare() public view {
        assertEq(keeperHandler.ghostSettleOnlyLosses(), 0);
    }

    function invariant_settledEpochsHoldWhatTheirPlanMovedThroughEscrow() public view {
        assertEq(keeperHandler.ghostSettlementMismatches(), 0);
    }

    function invariant_settlementPaysNoFlowMoreThanItsProRataPart() public view {
        assertEq(keeperHandler.ghostSettlementBreaches(), 0);
        assertEq(keeperHandler.ghostSettlementsUnmeasured(), 0);
    }

    function invariant_sentinelPlansLeaveThePayoutsTheirQueueStepsPay() public view {
        assertEq(keeperHandler.ghostSentinelPayoutShortfalls(), 0);
    }

    function invariant_claimsPayNoMoreThanTheirProRataPartAndGoThrough() public view {
        assertEq(handler.ghostClaimBreaks(), 0);
        assertEq(handler.ghostClaimRefusals(), 0);
    }

    function invariant_noPlanLosesMoreThanMaxShortfallPerShareAtTheTrustedPrice() public view {
        assertEq(keeperHandler.ghostLossBoundBreaches(), 0);
    }

    function invariant_noPlanMakesMoreThanOneSwap() public view {
        assertEq(keeperHandler.ghostMultiSwapPlans(), 0);
    }

    function invariant_rangesStayWithinTheirCaps() public view {
        uint256 length = almCore.getRangesLength();

        assertLe(length, ConfigLib.MAX_RANGE_CAP);
        assertLe(length, FixedPointMathLib.max(almCore.rangeCap_(), governanceHandler.ghostRangesAtCapMove()));
    }

    function invariant_boundedSyncCallsKeepTheirLimits() public view {
        assertEq(vaultHandler.ghostLimitBreaches(), 0);
    }

    function invariant_syncFlowsKeepWhatARemainingShareIsOwedInKind() public view {
        assertEq(vaultHandler.ghostInKindFalls(), 0);
    }

    function invariant_noUnauthorizedCallerMovesAnothersShares() public view {
        assertEq(handler.ghostUnauthorizedMoves(), 0);
    }

    function invariant_aSettledRequestIsNeverCancelled() public view {
        assertEq(handler.ghostSettledCancelBreaks(), 0);
    }

    function invariant_rewardPayoutsStayWithinTheRewardBalance() public view {
        assertEq(handler.ghostPayoutsAboveRewardBalance(), 0);
    }

    function invariant_plansKeepTheMinimumIntervalAndTheRangeCap() public view {
        assertEq(keeperHandler.ghostPlanSpacingBreaches(), 0);
        assertEq(keeperHandler.ghostRangeCapBreaches(), 0);
    }

    function invariant_neverTouchesAPositionInsideItsPenaltyWindow() public view {
        assertEq(keeperHandler.ghostWindowTouches(), 0);
    }

    function invariant_everyRangeHoldsOneUnstakedPositionAndAtMostOneSibling() public view {
        uint256 length = almCore.getRangesLength();
        for (uint256 i; i < length; ++i) {
            Range memory range = almCore.getRange(i);
            assertTrue(range.unstakedTokenId != 0);
            assertTrue(range.stakedTokenId != range.unstakedTokenId);
            assertEq(POSITION_MANAGER.ownerOf(range.unstakedTokenId), address(almCore));

            if (range.stakedTokenId == 0) {
                assertEq(range.stakedLiquidity, 0);
                continue;
            }
            (int24 tickLower, int24 tickUpper) = positionTicks(range.stakedTokenId);
            assertEq(tickLower, range.tickLower);
            assertEq(tickUpper, range.tickUpper);
            assertTrue(ICLGauge(address(gauge)).stakedContains(address(almCore), range.stakedTokenId));

            for (uint256 j = i + 1; j < length; ++j) {
                assertTrue(almCore.getRange(j).stakedTokenId != range.stakedTokenId);
            }
        }
    }

    function invariant_rangeLiquidityMatchesItsPositions() public view {
        uint256 length = almCore.getRangesLength();
        for (uint256 i; i < length; ++i) {
            Range memory range = almCore.getRange(i);
            INonfungiblePositionManager.Position memory unstaked = POSITION_MANAGER.positions(range.unstakedTokenId);
            assertEq(unstaked.tickLower, range.tickLower);
            assertEq(unstaked.tickUpper, range.tickUpper);
            assertEq(range.stakedTokenId != 0, range.stakedLiquidity != 0);
            if (range.stakedTokenId != 0) {
                assertEq(POSITION_MANAGER.positions(range.stakedTokenId).liquidity, range.stakedLiquidity);
                assertEq(POSITION_MANAGER.ownerOf(range.stakedTokenId), address(gauge));
            }
            for (uint256 j; j < length; ++j) {
                if (j != i) assertTrue(almCore.getRange(j).unstakedTokenId != range.unstakedTokenId);
                assertTrue(almCore.getRange(j).stakedTokenId != range.unstakedTokenId);
            }
        }
        assertEq(
            IERC721(address(POSITION_MANAGER)).balanceOf(address(almCore)), length + donorHandler.ghostDonatedTokenIds()
        );
    }

    function invariant_configStaysWithinItsLimits() public view {
        assertLe(almCore.protocolEmissionFeeBps_(), ConfigLib.MAX_FEE_BPS);
        assertLe(almCore.protocolSwapFeeBps_(), ConfigLib.MAX_FEE_BPS);
        assertLe(almCore.rangeCap_(), ConfigLib.MAX_RANGE_CAP);
        assertLe(almCore.maxShortfallBps_(), ConfigLib.BPS_DENOMINATOR);
        assertLt(almCore.maxSwapCostBps_(), ConfigLib.BPS_DENOMINATOR);
        assertGt(almCore.twapWindow_(), 0);
    }

    function invariant_coreIsUnlockedBetweenCalls() public view {
        assertFalse(coreViewLogic.isLocked(address(almCore)));
    }

    function invariant_viewsNeverRevert() public view {
        for (uint256 i; i < handler.actorsLength() + 3; ++i) {
            address holder = handler.holderAt(i);
            assertFalse(vaultHandler.viewsRevert(holder));
            assertFalse(handler.viewsRevert(holder, address(lens)));
        }
    }

    function invariant_syncCallsWithinTheirMaxViewsGoThroughAtTheirPreviews() public view {
        assertEq(vaultHandler.ghostMaxRefusals(), 0);
        assertEq(vaultHandler.ghostPreviewBreaks(), 0);
        assertEq(handler.ghostMaxMintRefusals(), 0);
    }

    function invariant_roundTripsExtractNoValue() public view {
        assertEq(roundTripHandler.ghostRoundTripGains(), 0);
    }

    function invariant_onlyControllersAndOperatorsMoveRequests() public view {
        assertEq(handler.ghostUnauthorizedAsyncAccepted(), 0);
        assertEq(handler.ghostUnauthorizedWrongReasons(), 0);
    }

    function invariant_redeemRequestsCancelsAndClaimsStayOpenWhilePaused() public view {
        assertEq(handler.ghostPausedRefusals(), 0);
    }

    function invariant_feePayoutsPayTheBookedFeesToTheRecipient() public view {
        assertEq(handler.ghostFeePayoutBreaks(), 0);
    }

    function invariant_aClaimPaysTheRewardOwedBeforeIt() public view {
        assertEq(handler.ghostOwedClaimBreaks(), 0);
    }

    function invariant_noPlanPaysAnAccountBeyondItsCancelledDeposits() public view {
        assertEq(keeperHandler.ghostPlanGains(), 0);
    }

    function invariant_everySwapStaysWithinTheMaxSwapCost() public view {
        assertEq(keeperHandler.ghostSwapCostBreaches(), 0);
    }

    function invariant_requestsMoveOnlyAlongTheirStateMachine() public view {
        assertEq(handler.ghostIllegalRequestMoves(), 0);
    }

    function invariant_everyClearedEpochSettlesOnceAndOnlyDrainsAfter() public view {
        assertEq(handler.ghostEpochResettles(), 0);
        assertEq(handler.ghostSettlementEventMismatches(), 0);
        for (uint256 q; q < 2 * handler.asyncVaultsLength(); ++q) {
            address vault = handler.asyncVaultAt(q / 2);
            bool isDeposit = q % 2 == 0;
            (uint32 pendingDepositEpoch, uint32 pendingRedeemEpoch) = almCore.pendingEpochs(vault);
            (uint32 lastClearedDepositEpoch, uint32 lastClearedRedeemEpoch) = almCore.lastClearedEpochs(vault);
            uint32 pendingEpoch = isDeposit ? pendingDepositEpoch : pendingRedeemEpoch;
            uint32 lastClearedEpoch = isDeposit ? lastClearedDepositEpoch : lastClearedRedeemEpoch;
            if (handler.ghostQueueSettled(vault, isDeposit)) assertTrue(pendingEpoch != lastClearedEpoch);
            for (uint32 e; e <= FixedPointMathLib.max(pendingEpoch, lastClearedEpoch); ++e) {
                if (e == pendingEpoch) continue;
                Epoch memory epoch = isDeposit ? almCore.depositEpoch(vault, e) : almCore.redeemEpoch(vault, e);
                bool settled = handler.ghostEpochSettled(vault, isDeposit, e);
                if (epoch.amountIn != 0) assertTrue(settled);
                if (!settled) continue;
                Epoch memory booked = handler.settledEpoch(vault, isDeposit, e);
                assertLe(epoch.amountIn, booked.amountIn);
                assertLe(epoch.amountOut, booked.amountOut);
            }
        }
    }

    function invariant_rangesMoveOnlyThroughTheirSteps() public view {
        assertEq(keeperHandler.ghostIllegalRangeMoves(), 0);
    }

    function invariant_refusedStepsRevertForTheirReason() public view {
        assertEq(keeperHandler.ghostRefusedStepsAccepted(), 0);
        assertEq(keeperHandler.ghostWrongRefusals(), 0);
    }

    function invariant_plansRunExactlyInsideBothTrustedBands() public view {
        assertEq(keeperHandler.ghostTrustedOutsideAccepts(), 0);
        assertEq(keeperHandler.ghostTrustedInsideRefusals(), 0);
    }

    function invariant_anEmptyPlanRunsInsideBothBands() public view {
        assertEq(keeperHandler.ghostEmptyPlanRefusals(), 0);
    }

    function invariant_lowerOnlyCapCallsNeverHoldOrRaise() public view {
        assertEq(governanceHandler.ghostNonLoweringAccepted(), 0);
        assertEq(governanceHandler.ghostNonLoweringWrongReasons(), 0);
    }

    function invariant_deadSharesSupplyFloorAndExchangeRateStaySet() public view {
        (, uint160 lastSqrtPriceX96) = almCore.lastExchangeRate_();

        assertEq(almCore.balanceOf(deadAddress), Constants.DEAD_SHARES);
        assertGe(almCore.totalSupply(), Constants.DEAD_SHARES);
        assertTrue(lastSqrtPriceX96 != 0);
    }

    function afterInvariant() public {
        // Then: Holders' pro-rata claims sum to the holdings, short by roundings.
        address[] memory holders = new address[](handler.actorsLength() + 3);
        for (uint256 i; i < holders.length; ++i) {
            holders[i] = handler.holderAt(i);
        }

        uint256 held0 = almCore.bufferAmount0();
        uint256 held1 = almCore.bufferAmount1();
        uint256 claimed0;
        uint256 claimed1;
        for (uint256 i; i < holders.length; ++i) {
            claimed0 += held0.fullMulDiv(almCore.balanceOf(holders[i]), almCore.totalSupply());
            claimed1 += held1.fullMulDiv(almCore.balanceOf(holders[i]), almCore.totalSupply());
        }
        // And: Each claim is its pro-rata liquidity and buffer, rounded down.
        for (uint256 r; r < almCore.getRangesLength(); ++r) {
            Range memory range = almCore.getRange(r);
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    sqrtPriceX96(pool),
                    range.tickLower,
                    range.tickUpper,
                    positionLiquidity(range.unstakedTokenId) + range.stakedLiquidity
                );
                (held0, held1) = (held0 + amount0, held1 + amount1);
            }
            for (uint256 i; i < holders.length; ++i) {
                uint128 owed = uint128(
                    (uint256(positionLiquidity(range.unstakedTokenId)) + range.stakedLiquidity)
                    .fullMulDiv(almCore.balanceOf(holders[i]), almCore.totalSupply())
                );
                (uint256 amount0, uint256 amount1) =
                    amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, owed);
                (claimed0, claimed1) = (claimed0 + amount0, claimed1 + amount1);
            }
        }
        assertLe(claimed0, held0);
        assertLe(claimed1, held1);

        // And: The shortfall is a floor per holder plus a liquidity unit per range.
        {
            (uint256 rounding0, uint256 rounding1) = (holders.length, holders.length);
            for (uint256 r; r < almCore.getRangesLength(); ++r) {
                Range memory range = almCore.getRange(r);
                (uint256 amount0, uint256 amount1) =
                    amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, uint128(holders.length));
                (rounding0, rounding1) = (rounding0 + amount0 + holders.length, rounding1 + amount1 + holders.length);
            }
            assertLe(held0 - claimed0, rounding0);
            assertLe(held1 - claimed1, rounding1);
        }

        // Given: The chain mints, windows closed, every holder's reward credited.
        if (!handler.isMintable()) return;
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
        for (uint256 i; i < holders.length - 1; ++i) {
            almCore.updateRewards(holders[i]);
        }

        // When: Every holder claims.
        uint256 unhealed;
        for (uint256 i; i < holders.length - 1; ++i) {
            almCore.claimEmissions(holders[i]);
            unhealed += almCore.getPendingReward(holders[i]);
        }

        // Then: Unpaid claims are at most the reward deficit and the net earned.
        (,, uint256 total) = almCore.getRewardTotals();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        earned -= earned * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        assertLe(unhealed, (highWater > total ? highWater - total : 0) + earned);
    }
}
