/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC7540Operator } from "../../../src/vaults/abstracts/tokens/ERC7540Operator.sol";

/**
 * @notice Fuzz tests for the function "deposit" of contract "ALMVaultAsync".
 */
// forge-lint: disable-next-item(reentrancy-events)
contract Deposit_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_deposit_Unauthorized(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        address caller,
        bool isToken0
    ) public {
        // Given: A seeded core, a settled deposit of the controller, and another caller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        vm.assume(caller != controller);

        // When: The caller claims it.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC7540Operator.Unauthorized.selector);
        vault.deposit(claimableIn, caller, controller);
    }

    function testFuzz_Revert_deposit_InsufficientClaimable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 excess,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        excess = bound(excess, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The controller claims more than was settled.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.deposit(claimableIn + excess, controller);
    }

    function testFuzz_Revert_deposit_InsufficientClaimable_EmptyPile(
        PoolState memory poolState,
        uint256 assets,
        bool isToken0
    ) public {
        // Given: The vaults over a pool, and nothing settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // When: The controller claims.
        // Then: It reverts.
        vm.prank(controller);
        vm.expectRevert(ALMVaultAsync.InsufficientClaimable.selector);
        vault.deposit(assets, controller);
    }

    function testFuzz_Success_deposit_ReadsNoPile(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, and a settled claim for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 assets = almCore.claimableDeposit(address(vault), controller).amountIn;

        // When: The controller claims all of it.
        vm.expectCall(address(almCore), abi.encodeWithSelector(bytes4(0xdbd035ff)), 0);
        vm.expectCall(address(almCore), abi.encodeWithSelector(bytes4(0x35fd631a)), 0);
        vm.expectCall(address(almCore), abi.encodeWithSelector(bytes4(0x1e2eaeaf)), 0);
        vm.prank(controller);
        vault.deposit(assets, controller);

        // Then: The vault read no storage of the core, and nothing stays claimable.
        assertEq(almCore.claimableDeposit(address(vault), controller).amountIn, 0);
    }

    function testFuzz_Success_deposit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;

        // When: The controller claims all of it to another account.
        vm.prank(controller);
        vm.expectEmit(address(vault));
        emit BaseVault.Deposit(controller, secondController, claimableIn, claimableOut);
        uint256 shares = vault.deposit(claimableIn, secondController);

        // Then: The receiver holds all shares the settlement left, none stay claimable.
        assertEq(shares, claimableOut);
        assertEq(almCore.balanceOf(secondController), claimableOut);
        assertEq(vault.maxDeposit(controller), 0);
    }

    function testFuzz_Success_deposit_RoundsAgainstTheCaller(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 part,
        bool isToken0
    ) public {
        // Given: A seeded core, a settled deposit of the controller, and a part of it.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;
        part = bound(part, 1, claimableIn);

        // When: The controller claims against that part.
        vm.prank(controller);
        uint256 shares = vault.deposit(part, controller);

        // Then: It received the part's share of the pile rounded down, and the part left.
        assertEq(shares, part * claimableOut / claimableIn);
        assertEq(almCore.balanceOf(controller), shares);
        assertEq(vault.maxDeposit(controller), claimableIn - part);
    }

    function testFuzz_Success_deposit_InTwoParts(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 part,
        bool isToken0
    ) public {
        // Given: A seeded core, and a deposit the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;
        part = bound(part, 1, claimableIn);

        // When: The controller claims it in two parts.
        vm.startPrank(controller);
        uint256 first = vault.deposit(part, controller);
        uint256 second = claimableIn > part ? vault.deposit(claimableIn - part, controller) : 0;
        vm.stopPrank();

        // Then: The two parts add up to all shares the settlement left, none lost.
        assertEq(first + second, claimableOut);
        assertEq(almCore.balanceOf(controller), claimableOut);
    }

    function testFuzz_Success_deposit_ByOperator(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core, a settled deposit of the controller, and its operator.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setDepositClaimable(poolState, range, queueState, isToken0, controller);
        uint256 claimableIn = almCore.claimableDeposit(address(vault), controller).amountIn;
        uint256 claimableOut = almCore.claimableDeposit(address(vault), controller).amountOut;
        vm.prank(controller);
        vault.setOperator(secondController, true);

        // When: The operator claims it to itself.
        vm.prank(secondController);
        vault.deposit(claimableIn, secondController, controller);

        // Then: The operator holds the shares.
        assertEq(almCore.balanceOf(secondController), claimableOut);
    }
}
