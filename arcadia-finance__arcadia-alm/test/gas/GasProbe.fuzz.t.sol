/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "../fuzz/ALMVaultSync/_ALMVaultSync.fuzz.t.sol";
import { ConfigLib } from "../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../src/interfaces/IALMSyncExtension.sol";
import { Plan } from "../utils/Plan.sol";
import { Range } from "../../src/core/types/Range.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Vm } from "@forge-std/Vm.sol";

/**
 * @notice Deterministic gas probe, one call per test, read with --isolate.
 */
// forge-lint: disable-next-item(unused-return)
contract GasProbe_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function test_Success_deposit_Token0() public {
        // Given: A seeded vault over token0 with one range.
        ALMVaultSync vault = gasProbeVault(true, 1);

        // And: A caller funded for a deposit within the vault's slippage.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 assets = bound(1e40, 1, maxAssets);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Token0");
    }

    function test_Success_deposit_Token1() public {
        // Given: A seeded vault over token1 with one range.
        ALMVaultSync vault = gasProbeVault(false, 1);

        // And: A caller funded for a deposit within the vault's slippage.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 assets = bound(1e40, 1, maxAssets);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Token1");
    }

    function test_Success_mint_Token0() public {
        // Given: A seeded vault over token0 with one range.
        ALMVaultSync vault = gasProbeVault(true, 1);

        // And: A caller funded for a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Token0");
    }

    function test_Success_mint_Token1() public {
        // Given: A seeded vault over token1 with one range.
        ALMVaultSync vault = gasProbeVault(false, 1);

        // And: A caller funded for a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Token1");
    }

    function test_Success_redeem_Token0() public {
        // Given: A seeded vault over token0 with one range.
        ALMVaultSync vault = gasProbeVault(true, 1);

        // And: A holder that approved a redeem within the vault's slippage.
        uint256 most = redeemableWithinSlippage(vault);
        uint256 shares = bound(1e40, 1, most);
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Token0");
    }

    function test_Success_redeem_Token1() public {
        // Given: A seeded vault over token1 with one range.
        ALMVaultSync vault = gasProbeVault(false, 1);

        // And: A holder that approved a redeem within the vault's slippage.
        uint256 most = redeemableWithinSlippage(vault);
        uint256 shares = bound(1e40, 1, most);
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Token1");
    }

    function test_Success_withdraw_Token0() public {
        // Given: A seeded vault over token0 with one range.
        ALMVaultSync vault = gasProbeVault(true, 1);

        // And: A holder that approved the vault, and half of a redeem within its slippage.
        approveVault(users.steward, vault, type(uint256).max);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 assets = vault.previewRedeem(bound(1e40, 1, most)) / 2;

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Token0");
    }

    function test_Success_withdraw_Token1() public {
        // Given: A seeded vault over token1 with one range.
        ALMVaultSync vault = gasProbeVault(false, 1);

        // And: A holder that approved the vault, and half of a redeem within its slippage.
        approveVault(users.steward, vault, type(uint256).max);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 assets = vault.previewRedeem(bound(1e40, 1, most)) / 2;

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Token1");
    }

    function test_Success_deposit_Token0AtThreeRanges() public {
        // Given: A seeded vault over token0 with three ranges.
        ALMVaultSync vault = gasProbeVault(true, 3);

        // And: A caller funded for a deposit within the vault's slippage.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 assets = bound(1e40, 1, maxAssets);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Token0AtThreeRanges");
    }

    function test_Success_deposit_Token1AtThreeRanges() public {
        // Given: A seeded vault over token1 with three ranges.
        ALMVaultSync vault = gasProbeVault(false, 3);

        // And: A caller funded for a deposit within the vault's slippage.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 assets = bound(1e40, 1, maxAssets);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Token1AtThreeRanges");
    }

    function test_Success_mint_Token0AtThreeRanges() public {
        // Given: A seeded vault over token0 with three ranges.
        ALMVaultSync vault = gasProbeVault(true, 3);

        // And: A caller funded for a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Token0AtThreeRanges");
    }

    function test_Success_mint_Token1AtThreeRanges() public {
        // Given: A seeded vault over token1 with three ranges.
        ALMVaultSync vault = gasProbeVault(false, 3);

        // And: A caller funded for a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Token1AtThreeRanges");
    }

    function test_Success_redeem_Token0AtThreeRanges() public {
        // Given: A seeded vault over token0 with three ranges.
        ALMVaultSync vault = gasProbeVault(true, 3);

        // And: A holder that approved a redeem within the vault's slippage.
        uint256 most = redeemableWithinSlippage(vault);
        uint256 shares = bound(1e40, 1, most);
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Token0AtThreeRanges");
    }

    function test_Success_redeem_Token1AtThreeRanges() public {
        // Given: A seeded vault over token1 with three ranges.
        ALMVaultSync vault = gasProbeVault(false, 3);

        // And: A holder that approved a redeem within the vault's slippage.
        uint256 most = redeemableWithinSlippage(vault);
        uint256 shares = bound(1e40, 1, most);
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Token1AtThreeRanges");
    }

    function test_Success_withdraw_Token0AtThreeRanges() public {
        // Given: A seeded vault over token0 with three ranges.
        ALMVaultSync vault = gasProbeVault(true, 3);

        // And: A holder that approved the vault, and half of a redeem within its slippage.
        approveVault(users.steward, vault, type(uint256).max);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 assets = vault.previewRedeem(bound(1e40, 1, most)) / 2;

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Token0AtThreeRanges");
    }

    function test_Success_withdraw_Token1AtThreeRanges() public {
        // Given: A seeded vault over token1 with three ranges.
        ALMVaultSync vault = gasProbeVault(false, 3);

        // And: A holder that approved the vault, and half of a redeem within its slippage.
        approveVault(users.steward, vault, type(uint256).max);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 assets = vault.previewRedeem(bound(1e40, 1, most)) / 2;

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Token1AtThreeRanges");
    }

    function test_Success_deposit_Token0AtRangeCap() public {
        // Given: A seeded vault over token0 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(true);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A caller funded for a deposit within the vault's slippage.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 assets = bound(1e40, 1, maxAssets);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Token0AtRangeCap");
    }

    function test_Success_deposit_Token1AtRangeCap() public {
        // Given: A seeded vault over token1 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(false);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A caller funded for a deposit within the vault's slippage.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 assets = bound(1e40, 1, maxAssets);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Token1AtRangeCap");
    }

    function test_Success_mint_Token0AtRangeCap() public {
        // Given: A seeded vault over token0 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(true);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A caller funded for a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Token0AtRangeCap");
    }

    function test_Success_mint_Token1AtRangeCap() public {
        // Given: A seeded vault over token1 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(false);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A caller funded for a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), vault.previewMint(shares), address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Token1AtRangeCap");
    }

    function test_Success_redeem_Token0AtRangeCap() public {
        // Given: A seeded vault over token0 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(true);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A holder that approved a redeem within the vault's slippage.
        uint256 most = redeemableWithinSlippage(vault);
        uint256 shares = bound(1e40, 1, most);
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Token0AtRangeCap");
    }

    function test_Success_redeem_Token1AtRangeCap() public {
        // Given: A seeded vault over token1 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(false);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A holder that approved a redeem within the vault's slippage.
        uint256 most = redeemableWithinSlippage(vault);
        uint256 shares = bound(1e40, 1, most);
        approveVault(users.steward, vault, shares);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Token1AtRangeCap");
    }

    function test_Success_withdraw_Token0AtRangeCap() public {
        // Given: A seeded vault over token0 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(true);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A holder that approved the vault, and half of a redeem within its slippage.
        approveVault(users.steward, vault, type(uint256).max);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 assets = vault.previewRedeem(bound(1e40, 1, most)) / 2;

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Token0AtRangeCap");
    }

    function test_Success_withdraw_Token1AtRangeCap() public {
        // Given: A seeded vault over token1 with as many ranges as the range cap.
        ALMVaultSync vault = gasProbeVaultAtCap(false);
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());

        // And: A holder that approved the vault, and half of a redeem within its slippage.
        approveVault(users.steward, vault, type(uint256).max);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 assets = vault.previewRedeem(bound(1e40, 1, most)) / 2;

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Token1AtRangeCap");
    }

    function test_Success_transfer() public {
        // Given: A seeded core.
        gasProbeCore();

        // And: A thousandth of the holder's shares.
        uint256 shares = almCore.balanceOf(users.steward) / 1000;

        // When: The holder transfers them.
        vm.prank(users.steward);
        almCore.transfer(accountA, shares);
        // Then: The call's gas is logged.
        logGas("test_Success_transfer");
    }

    function test_Success_claimEmissions() public {
        // Given: A seeded core.
        gasProbeCore();

        // When: Claiming the holder's emissions.
        almCore.claimEmissions(users.steward);
        // Then: The call's gas is logged.
        logGas("test_Success_claimEmissions");
    }

    function test_Success_recordDepositRequest() public {
        // Given: A seeded core.
        uint256 assets = gasProbeCore();

        // And: Assets the token0 vault moved to the core.
        token0.mint(address(almCore), assets);

        // When: The vault records the request.
        vm.prank(asyncVault0);
        almCore.recordDepositRequest(controller, assets);
        // Then: The call's gas is logged.
        logGas("test_Success_recordDepositRequest");
    }

    function test_Success_claimDepositRequest() public {
        // Given: A seeded core.
        uint256 assets = gasProbeCore();

        // And: A settled deposit record.
        recordDepositAt(asyncVault0, controller, assets);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // When: The vault claims half of it.
        vm.prank(asyncVault0);
        almCore.claimDepositRequest(controller, assets / 2, type(uint256).max, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_claimDepositRequest");
    }

    function test_Success_deposit_Async() public {
        // Given: A seeded core and a deposit the keeper settled for the controller.
        uint256 assets = gasProbeCore();
        recordDepositAt(asyncVault0, controller, assets);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // When: The controller claims against half of it through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).deposit(assets / 2, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_deposit_Async");
    }

    function test_Success_mint_Async() public {
        // Given: A seeded core and a deposit the keeper settled for the controller.
        uint256 assets = gasProbeCore();
        recordDepositAt(asyncVault0, controller, assets);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());
        uint256 shares = ALMVaultAsync(asyncVault0).maxMint(controller) / 2;

        // When: The controller claims half its shares through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).mint(shares, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_mint_Async");
    }

    function test_Success_redeem_Async() public {
        // Given: A seeded core and a redeem the keeper settled for the controller.
        gasProbeCore();
        uint256 shares = almCore.totalSupply() / 1000;
        recordRedeemAt(asyncVault0, controller, shares);
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // When: The controller claims against half of it through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).redeem(shares / 2, controller, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_redeem_Async");
    }

    function test_Success_withdraw_Async() public {
        // Given: A seeded core and a redeem the keeper settled for the controller.
        gasProbeCore();
        recordRedeemAt(asyncVault0, controller, almCore.totalSupply() / 1000);
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());
        uint256 assets = ALMVaultAsync(asyncVault0).maxWithdraw(controller) / 2;

        // When: The controller claims half its assets through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).withdraw(assets, controller, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_withdraw_Async");
    }

    function test_Success_requestDeposit_Async() public {
        // Given: A seeded core.
        uint256 assets = gasProbeCore();

        // And: A controller holding assets approved to the token0 vault.
        token0.mint(controller, assets);
        vm.prank(controller);
        token0.approve(asyncVault0, assets);

        // When: The controller requests a deposit through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).requestDeposit(assets, controller, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_requestDeposit_Async");
    }

    function test_Success_requestRedeem_Async() public {
        // Given: A seeded core.
        gasProbeCore();

        // And: A controller holding a thousandth of the supply.
        uint256 shares = almCore.totalSupply() / 1000;
        almCore.mintShares(controller, shares);

        // When: The controller requests a redeem through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).requestRedeem(shares, controller, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_requestRedeem_Async");
    }

    function test_Success_cancelDepositRequest_Async() public {
        // Given: A seeded core and a pending deposit of the controller.
        uint256 assets = gasProbeCore();
        recordDepositAt(asyncVault0, controller, assets);

        // When: The controller cancels it through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).cancelDepositRequest(0, controller, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_cancelDepositRequest_Async");
    }

    function test_Success_cancelRedeemRequest_Async() public {
        // Given: A seeded core and a pending redeem of the controller.
        gasProbeCore();
        recordRedeemAt(asyncVault0, controller, almCore.totalSupply() / 1000);

        // When: The controller cancels it through the token0 vault.
        vm.prank(controller);
        ALMVaultAsync(asyncVault0).cancelRedeemRequest(0, controller, controller);
        // Then: The call's gas is logged.
        logGas("test_Success_cancelRedeemRequest_Async");
    }

    function test_Success_execute_CancelDepositsAndRedeems() public {
        // Given: A seeded core.
        uint256 assets = gasProbeCore();

        // And: A pending deposit and a pending redeem of the controller.
        uint256 shares = almCore.totalSupply() / 1000;
        recordDepositAt(asyncVault0, controller, assets);
        recordRedeemAt(asyncVault0, controller, shares);

        // When: The keeper cancels both.
        runPlan(
            Plan.init()
                .cancelRequests(true, true, Plan.one(controller))
                .cancelRequests(true, false, Plan.one(controller))
        );
        // Then: The call's gas is logged.
        logGas("test_Success_execute_CancelDepositsAndRedeems");
    }

    function test_Success_execute_SettleAndSwap() public {
        // Given: A seeded core.
        uint256 assets = gasProbeCore();

        // And: A pending deposit and a pending redeem.
        recordDepositAt(asyncVault0, controller, assets);
        recordRedeemAt(asyncVault0, secondController, almCore.totalSupply() / 1000);

        // When: The keeper settles both and swaps.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(true, false)
                .swapViaPool(true, assets, TickMath.MIN_SQRT_PRICE + 1, 0)
                .settleRequests()
        );
        // Then: The call's gas is logged.
        logGas("test_Success_execute_SettleAndSwap");
    }

    function test_Success_execute_SettleDeposits() public {
        // Given: A seeded core.
        gasProbeCore();

        // And: A pending token0 deposit.
        recordDepositAt(asyncVault0, controller, 1e24);

        // When: The keeper settles it.
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());
        // Then: The call's gas is logged.
        logGas("test_Success_execute_SettleDeposits");
    }

    function test_Success_execute_FourSettlesAndSwap() public {
        // Given: A seeded core.
        gasProbeCore();

        // And: A pending deposit and a pending redeem in each vault.
        uint256 shares = almCore.totalSupply() / 1000;
        recordDepositAt(asyncVault0, controller, 1e24);
        recordDepositAt(asyncVault1, controller, 1e24);
        recordRedeemAt(asyncVault0, secondController, shares);
        almCore.mintShares(secondController, shares);
        vm.prank(asyncVault1);
        almCore.recordRedeemRequest(secondController, secondController, secondController, shares);

        // When: The keeper settles all four and swaps.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, true)
                .clearAllRequests(false, false)
                .swapViaPool(true, 1e24, TickMath.MIN_SQRT_PRICE + 1, 0)
                .settleRequests()
        );
        // Then: The call's gas is logged.
        logGas("test_Success_execute_FourSettlesAndSwap");
    }

    function test_Success_execute_SwapOnly() public {
        // Given: A seeded core.
        gasProbeCore();

        // And: A thousandth of the token0 buffer.
        uint256 assets = almCore.bufferAmount0() / 1000;

        // When: The keeper swaps it.
        runPlan(Plan.init().swapViaPool(true, assets, TickMath.MIN_SQRT_PRICE + 1, 0));
        // Then: The call's gas is logged.
        logGas("test_Success_execute_SwapOnly");
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function gasProbeVault(bool isToken0, uint256 rangeCount) internal returns (ALMVaultSync vault) {
        PoolState memory poolState;
        CoreState memory coreState;
        RangeState memory range;
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        poolState.liquidityPool = type(uint128).max;
        coreState.supply = 1e40;
        coreState.buffer0 = 1e40;
        coreState.buffer1 = 1e40;
        range.tickLower = -3000;
        range.tickUpper = 3000;
        range.liquidity = type(uint128).max;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(100);

        if (rangeCount < 3) return vault;

        RangeState memory next;
        next.liquidity = range.liquidity / 2;
        (next.tickLower, next.tickUpper) = (range.tickLower - poolState.tickSpacing, range.tickUpper);
        setRangeState(next);
        (next.tickLower, next.tickUpper) = (range.tickLower, range.tickUpper + poolState.tickSpacing);
        setRangeState(next);
        for (int24 step = 2; almCore.getRangesLength() < rangeCount; ++step) {
            next.tickLower = range.tickLower - step * poolState.tickSpacing;
            next.tickUpper = range.tickUpper + step * poolState.tickSpacing;
            setRangeState(next);
        }
    }

    function gasProbeVaultAtCap(bool isToken0) internal returns (ALMVaultSync vault) {
        vault = gasProbeVault(isToken0, ConfigLib.MAX_RANGE_CAP);
    }

    function gasProbeCore() internal returns (uint256 assets) {
        PoolState memory poolState;
        CoreState memory coreState;
        QueueState memory queueState;
        RangeState memory range;
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        poolState.liquidityPool = type(uint128).max;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        range.tickLower = -3000;
        range.tickUpper = 3000;
        range.liquidity = type(uint128).max;
        range.liquidityStaked = type(uint128).max;
        givenValidRangeState(range, poolState, false);
        range.liquidity = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4;
        range.liquidityStaked = range.liquidity;

        coreState.supply = 1e40;
        coreState.buffer0 = 1e40;
        coreState.buffer1 = 1e40;
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        vm.prank(factory);
        almCore.setPlanLimits(Constants.WIDE_MAX_SHORTFALL_BPS, 100, 0);

        queueState.deposit0 = type(uint256).max;
        givenValidQueueState(queueState, 0, 0);
        assets = queueState.deposit0;
    }

    function logGas(string memory name) internal {
        Vm.Gas memory gas = vm.lastFrameGas();
        uint256 refund = gas.gasRefunded > 0 ? uint256(int256(gas.gasRefunded)) : 0;
        uint256 cap = gas.gasTotalUsed / 5;
        emit log_named_uint(name, gas.gasTotalUsed);
        emit log_named_uint(string.concat(name, "_net"), gas.gasTotalUsed - (refund < cap ? refund : cap));
    }
}
