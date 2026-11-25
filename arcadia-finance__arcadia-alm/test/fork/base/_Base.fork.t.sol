/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMFactoryExtension } from "../../utils/extensions/ALMFactoryExtension.sol";
import { ALMFixture } from "../../utils/fixtures/alm/ALMFixture.f.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { Plan } from "../../utils/Plan.sol";
import { RouterTrampoline } from "../../utils/fixtures/asset-managers/RouterTrampoline.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Common logic needed by all Base fork tests.
 */
abstract contract Base_Fork_Test is ALMFixture {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    address internal constant METADEX_CL_GAUGE_FACTORY = 0xf437f62053ACB121665b8fDBfeA8F214FB8E589d;
    address internal constant METADEX_POSITION_MANAGER = 0x4857DB576eE0e45F10525eC59527BfD10beeC60b;
    address internal constant METADEX_VOTER = 0x382409fad8503FbCdbB27A4211551fa03e884078;
    address internal constant AERO = 0x3f5bF3EdAc59d650D8fDf9657a71F2f904A3a4Ee;

    address internal constant GAUGE_CL50_WETH_USDC = 0x46a9dCa72D78366571bE583aa69C1DC16E6889fB;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    address internal depositor;
    address internal feeRecipient;
    address internal keeper;
    address internal owner;
    address internal steward;

    IERC20 internal token0;
    IERC20 internal token1;

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal almCore;
    ALMFactoryExtension internal deployer;
    ICLPool internal pool;
    ALMVaultSync internal syncVault0;
    ALMVaultSync internal syncVault1;
    ALMVaultAsync internal asyncVault0;
    ALMVaultAsync internal asyncVault1;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("RPC_URL_BASE"));

        depositor = makeAddr("depositor");
        feeRecipient = makeAddr("feeRecipient");
        keeper = makeAddr("keeper");
        owner = makeAddr("owner");
        steward = makeAddr("steward");

        pool = ICLPool(ICLGauge(GAUGE_CL50_WETH_USDC).pool());
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        // Deploy the factory on the live Metadex stack, and a core with its vaults for the pool.
        CreationCodes memory codes = extensionCreationCodes();
        deployer = new ALMFactoryExtension(
            METADEX_POSITION_MANAGER,
            address(new RouterTrampoline()),
            METADEX_VOTER,
            METADEX_CL_GAUGE_FACTORY,
            AERO,
            false,
            owner,
            codeHashesOf(codes)
        );
        vm.prank(owner);
        deployer.setSteward(steward);
        vm.prank(steward);
        deployer.createExtensions(extensionDeployments(codes));
        almCore = ALMCoreExtension(createInThreeTransactions(deployer, address(pool), codes, steward, feeRecipient));
        Vaults memory vaults = deployer.getVaults(address(almCore));
        (syncVault0, syncVault1) = (ALMVaultSync(vaults.syncVault0), ALMVaultSync(vaults.syncVault1));
        (asyncVault0, asyncVault1) = (ALMVaultAsync(vaults.asyncVault0), ALMVaultAsync(vaults.asyncVault1));

        deployer.setIsKeeper(address(almCore), keeper, true);
        vm.startPrank(address(deployer));
        almCore.setPlanLimits(0, 0, 0);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        almCore.setPerUserCap(type(uint128).max);
        almCore.setRangeCap(ConfigLib.MAX_RANGE_CAP);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function seedCore(uint256 amount0, uint256 amount1) internal {
        // Seed the core with a supply of its value in token1 at spot.
        deal(address(token0), address(deployer), amount0);
        deal(address(token1), address(deployer), amount1);
        vm.startPrank(address(deployer));
        token0.approve(address(almCore), amount0);
        token1.approve(address(almCore), amount1);
        almCore.seed(amount0, amount1, amount1 + CLMath.convert(sqrtPriceX96(pool), true, amount0, false), steward);
        vm.stopPrank();
    }

    function setProtocolSwapFeeBps(uint256 protocolSwapFeeBps) internal {
        // Charge a protocol share of the core's swap fees, up to its maximum.
        protocolSwapFeeBps = bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(address(deployer));
        almCore.setProtocolFees(0, uint16(protocolSwapFeeBps), feeRecipient);
    }

    function openRange(int24 tickLower, int24 tickUpper) internal {
        // Open a range with the whole buffer.
        runStagingPlan(
            Plan.init().openRange(tickLower, tickUpper, almCore.bufferAmount0(), almCore.bufferAmount1(), 0, 0)
        );
    }

    function setMaxSwapCost(uint256 maxSwapCostBps) internal {
        // Draw a max swap cost above the pool's fee, the other plan limits kept.
        maxSwapCostBps = bound(maxSwapCostBps, pool.fee() / 100 + 1, ConfigLib.BPS_DENOMINATOR - 1);
        (uint256 maxShortfallBps, uint256 minPlanInterval) = (almCore.maxShortfallBps_(), almCore.minPlanInterval_());
        vm.prank(address(deployer));
        almCore.setPlanLimits(uint16(maxShortfallBps), uint16(maxSwapCostBps), uint32(minPlanInterval));
    }

    function runStagingPlan(Plan.Steps memory plan) internal {
        // Execute a plan at the shortfall a wei per step covers and no swap cost, the limits restored after it.
        (uint256 maxShortfallBps, uint256 maxSwapCostBps, uint256 minPlanInterval) =
            (almCore.maxShortfallBps_(), almCore.maxSwapCostBps_(), almCore.minPlanInterval_());
        setPlanLimits(0, 0, plan.commands.length, 0, 0);
        runPlan(plan);
        vm.prank(address(deployer));
        almCore.setPlanLimits(uint16(maxShortfallBps), uint16(maxSwapCostBps), uint32(minPlanInterval));
    }

    function setPlanLimits(
        uint256 maxShortfallBps,
        uint256 maxSwapCostBps,
        uint256 steps,
        uint256 loss,
        uint256 leastSwapCostBps
    ) internal {
        // Draw the limits, the shortfall from a wei per step and the loss over the buffer's value.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 value = almCore.bufferAmount1() + CLMath.convert(sqrtPrice, true, almCore.bufferAmount0(), false);
        loss += steps * (CLMath.convert(sqrtPrice, true, 1, false) + 2) + 1;
        maxShortfallBps = bound(
            maxShortfallBps,
            FixedPointMathLib.min(loss.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value), ConfigLib.BPS_DENOMINATOR),
            ConfigLib.BPS_DENOMINATOR
        );
        maxSwapCostBps = bound(maxSwapCostBps, leastSwapCostBps, ConfigLib.BPS_DENOMINATOR - 1);
        vm.prank(address(deployer));
        almCore.setPlanLimits(uint16(maxShortfallBps), uint16(maxSwapCostBps), 0);
    }

    function planSwap(Plan.Steps memory plan, bool zeroForOne) internal returns (uint256 amountIn, uint256 amountOut) {
        // The pool's side of a plan's swap, from a run at the widest limits that is rolled back.
        uint256 snapshot = vm.snapshotState();
        setPlanLimits(ConfigLib.BPS_DENOMINATOR, ConfigLib.BPS_DENOMINATOR - 1, 0, 0, 0);
        (IERC20 tokenIn, IERC20 tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);
        (amountIn, amountOut) = (tokenIn.balanceOf(address(pool)), tokenOut.balanceOf(address(pool)));
        runPlan(plan);
        (amountIn, amountOut) =
        (tokenIn.balanceOf(address(pool)) - amountIn, amountOut - tokenOut.balanceOf(address(pool)));
        vm.revertToState(snapshot);
    }

    function runPlan(Plan.Steps memory plan) internal {
        // Execute a plan as the keeper, trusting spot.
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function deposit(ALMVaultSync vault, uint256 assets) internal returns (uint256 shares) {
        deal(vault.asset(), depositor, assets);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), assets);
        shares = vault.deposit(assets, depositor);
        vm.stopPrank();
    }

    function spacedTick(int24 offset) internal view returns (int24 tick) {
        // The spaced tick at or below spot, moved by offset spacings.
        int24 spacing = pool.tickSpacing();
        tick = currentTick(pool);
        tick = (tick < 0 && tick % spacing != 0 ? tick / spacing - 1 : tick / spacing) * spacing + offset * spacing;
    }
}
