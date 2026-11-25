/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Accesses } from "../utils/Accesses.sol";
import { ALMVaultAsync } from "../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "../fuzz/ALMVaultAsync/_ALMVaultAsync.fuzz.t.sol";
import { ALMVaultSync } from "../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "../fuzz/ALMVaultSync/_ALMVaultSync.fuzz.t.sol";
import { Constants } from "../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../src/interfaces/IALMSyncExtension.sol";
import { Plan } from "../utils/Plan.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Fuzz tests that no depositor or holder path of contract "ALMCore" performs a DELEGATECALL.
 */
// forge-lint: disable-next-item(unused-return)
contract DelegateCallTrace_ALMCore_Fuzz_Test is ALMVaultSync_Fuzz_Test, ALMVaultAsync_Fuzz_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test, ALMVaultAsync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function spotState() internal view returns (CoreState memory coreState, RangeState memory range) {
        // And: One range ten spacings each side of spot, of liquidity 1e22.
        int24 tickSpacing = pool.tickSpacing();
        int24 tick = currentTick(pool);
        range.tickLower = (tick / tickSpacing - 10) * tickSpacing;
        range.tickUpper = (tick / tickSpacing + 10) * tickSpacing;
        range.liquidity = 1e22;

        // And: A core over 1e24 shares holding 1e24 of each token.
        coreState = CoreState({ supply: 1e24, buffer0: 1e24, buffer1: 1e24 });
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_execute_DelegatesOnce(uint256 amount) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);

        // And: A buffer swap of the least input or more that stays inside the range.
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        uint160 sqrtPriceLimitX96 = TickMath.getSqrtPriceAtTick(range.tickLower);
        uint256 ceiling = FixedPointMathLib.min(
            almCore.bufferAmount0(),
            SqrtPriceMath.getAmount0Delta(sqrtPriceLimitX96, trustedSqrtPriceX96, pool.liquidity(), false)
        );
        amount = bound(amount, leastSwapIn(true), ceiling);
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amount, sqrtPriceLimitX96, 0);

        // And: Plan limits at the swap's cost and the plan's loss.
        ConfigState memory configState;
        givenValidPlanLimits(configState, 1, true, amount, poolSwapOut(true, amount));
        setPlanLimits(configState);

        // When: The keeper executes it.
        vm.startStateDiffRecording();
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: The stub delegated into the keeper extension exactly once.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 1);
    }

    function testFuzz_Success_syncDeposit_NoDelegateCall(uint256 assets, bool isToken0) public {
        // Given: A seeded vault holding a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        // And: A deposit from a million wei to maxDeposit, and a funded caller.
        assets = bound(assets, 1e6, IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress));
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.startStateDiffRecording();
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_syncMint_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A seeded vault holding a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        // And: At most a hundredth of the supply, a caller funded far above its cost.
        shares = bound(
            shares,
            1,
            FixedPointMathLib.min(
                IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), almCore.totalSupply() / 100
            )
        );
        uint256 maxAssets = type(uint128).max;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), maxAssets, address(vault));

        // When: The caller mints.
        vm.startStateDiffRecording();
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_syncRedeem_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A seeded vault holding a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        // And: A seed receiver holding aLP that approved the vault.
        shares = bound(shares, 1, redeemableWithinSlippage(vault));
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.startStateDiffRecording();
        vm.prank(users.steward);
        vault.redeem(shares, controller, users.steward, 0);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_syncMintPlain_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A seeded vault holding a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        // And: At most a hundredth of the supply and maxMint, a caller funded for it.
        shares = bound(
            shares,
            1,
            FixedPointMathLib.min(
                IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), almCore.totalSupply() / 100
            )
        );
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints through the plain signature.
        vm.startStateDiffRecording();
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_syncRedeemPlain_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A seeded vault holding a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        // And: A seed receiver holding aLP that approved the vault.
        shares = bound(
            shares,
            1,
            FixedPointMathLib.min(
                redeemableWithinSlippage(vault), IALMSyncExtension(address(vault)).maxRedeem(users.steward)
            )
        );
        approveVault(users.steward, vault, shares);

        // When: The holder redeems via the plain signature, reading the core's totals.
        vm.startStateDiffRecording();
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_syncWithdraw_NoDelegateCall(uint256 assets, bool isToken0) public {
        // Given: A seeded vault holding a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        // And: A seed receiver holding aLP that approved the vault.
        approveVault(users.steward, vault, type(uint256).max);

        // And: An asset amount of at most what a redeem of half the redeemable aLP is quoted to pay and maxWithdraw.
        assets = bound(
            assets,
            1,
            FixedPointMathLib.min(
                vault.previewRedeem(redeemableWithinSlippage(vault) / 2),
                IALMSyncExtension(address(vault)).maxWithdraw(users.steward)
            )
        );

        // When: The holder withdraws.
        vm.startStateDiffRecording();
        vm.prank(users.steward);
        vault.withdraw(assets, controller, users.steward);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_transfer_NoDelegateCall(uint256 shares) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);

        // And: A seed receiver holding aLP.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));

        // When: The holder transfers.
        vm.startStateDiffRecording();
        vm.prank(users.steward);
        almCore.transfer(accountA, shares);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_transferFrom_NoDelegateCall(uint256 shares) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);

        // And: A seed receiver holding aLP that approved a spender.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.approve(accountB, shares);

        // When: The spender transfers.
        vm.startStateDiffRecording();
        vm.prank(accountB);
        almCore.transferFrom(users.steward, accountA, shares);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_requestDeposit_NoDelegateCall(uint256 assets, bool isToken0) public {
        // Given: A funded owner.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRequester(isToken0, controller, assets);

        // When: The owner requests a deposit.
        vm.startStateDiffRecording();
        vm.prank(controller);
        asyncVaultFor(isToken0).requestDeposit(assets, controller, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_requestRedeem_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: An owner holding shares the vault may take.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        fundRedeemer(controller, shares);

        // When: The owner requests a redeem.
        vm.startStateDiffRecording();
        vm.prank(controller);
        asyncVaultFor(isToken0).requestRedeem(shares, controller, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_cancelDepositRequest_NoDelegateCall(uint256 assets, bool isToken0) public {
        // Given: A pending deposit.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        requestDepositFor(isToken0, controller, assets);

        // When: The controller cancels it.
        vm.startStateDiffRecording();
        vm.prank(controller);
        asyncVaultFor(isToken0).cancelDepositRequest(0, controller, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_cancelRedeemRequest_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A pending redeem.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        requestRedeemFor(isToken0, controller, shares);

        // When: The controller cancels it.
        vm.startStateDiffRecording();
        vm.prank(controller);
        asyncVaultFor(isToken0).cancelRedeemRequest(0, controller, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_asyncDeposit_NoDelegateCall(uint256 assets, bool isToken0) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // And: A deposit from a million wei to a hundredth of the supply, settled.
        assets = bound(assets, 1e6, almCore.totalSupply() / 100);
        requestDepositFor(isToken0, controller, assets);
        settleDeposit(isToken0);
        vm.prank(controller);
        vault.deposit(0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;

        // When: The controller claims it.
        vm.startStateDiffRecording();
        vm.prank(controller);
        vault.deposit(claimableIn, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_asyncMint_NoDelegateCall(uint256 assets, bool isToken0) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // And: A deposit from a million wei to a hundredth of the supply, settled.
        assets = bound(assets, 1e6, almCore.totalSupply() / 100);
        requestDepositFor(isToken0, controller, assets);
        settleDeposit(isToken0);
        vm.prank(controller);
        vault.deposit(0, controller);
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;

        // When: The controller claims its shares.
        vm.startStateDiffRecording();
        vm.prank(controller);
        vault.mint(claimableOut, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_asyncRedeem_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // And: A redeem of a hundredth of the supply or less, settled from the buffers.
        shares = bound(shares, 1, almCore.totalSupply() / 100);
        requestRedeemFor(isToken0, controller, shares);
        settleRedeem(isToken0);
        vm.prank(controller);
        vault.redeem(0, controller, controller);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;

        // When: The controller claims it.
        vm.startStateDiffRecording();
        vm.prank(controller);
        vault.redeem(claimableIn, controller, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }

    function testFuzz_Success_asyncWithdraw_NoDelegateCall(uint256 shares, bool isToken0) public {
        // Given: A seeded core with a range around spot.
        (CoreState memory coreState, RangeState memory range) = spotState();
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // And: A redeem of a hundredth of the supply or less, settled from the buffers.
        shares = bound(shares, 1, almCore.totalSupply() / 100);
        requestRedeemFor(isToken0, controller, shares);
        settleRedeem(isToken0);
        vm.prank(controller);
        vault.redeem(0, controller, controller);
        uint256 claimableOut = almCore.claimableRedeem(address(vault), controller).amountOut;

        // When: The controller claims its assets.
        vm.startStateDiffRecording();
        vm.prank(controller);
        vault.withdraw(claimableOut, controller, controller);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Nothing delegated into an extension.
        assertEq(Accesses.delegateCallsInto(accesses, almCore.KEEPER_EXTENSION_(), almCore.ADMIN_EXTENSION_()), 0);
    }
}
