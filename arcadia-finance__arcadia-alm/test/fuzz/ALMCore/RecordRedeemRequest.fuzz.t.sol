/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { AsyncVaultGuard } from "../../../src/core/abstracts/mixins/AsyncVaultGuard.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "recordRedeemRequest" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return)
contract RecordRedeemRequest_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_recordRedeemRequest_InvalidController(address caller, address owner_, uint256 shares)
        public
    {
        // Given: A core as deployed.

        // When: Any caller records a redeem with the core as its controller.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMCore.InvalidController.selector);
        almCore.recordRedeemRequest(address(almCore), owner_, owner_, shares);
    }

    function testFuzz_Revert_recordRedeemRequest_OnlyAsyncVault(address caller, address controller, uint256 shares)
        public
    {
        // Given: A controller that is neither the zero address nor the core.
        vm.assume(controller != address(0) && controller != address(almCore));

        // And: A caller that is neither asynchronous vault.
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: Calling recordRedeemRequest().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.recordRedeemRequest(controller, controller, controller, shares);
    }

    function testFuzz_Revert_recordRedeemRequest_NoAllowance(address controller, address caller, uint256 shares)
        public
    {
        // Given: A controller holding the shares, and a caller it never approved.
        vm.assume(controller != address(0) && controller != address(almCore) && controller != asyncVault0);
        vm.assume(caller != controller);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(controller, shares);

        // When: The vault records the request for that caller.
        // Then: It reverts instead of recording shares the caller was never given.
        vm.prank(asyncVault0);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        almCore.recordRedeemRequest(controller, controller, caller, shares);
    }

    function testFuzz_Revert_recordRedeemRequest_ZeroAddress(address owner_, uint256 shares) public {
        // Given: An owner with the shares in its balance, the vault allowed to move them.
        vm.assume(owner_ != address(0) && owner_ != address(almCore));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(owner_, shares);

        // When: The vault records the request for no controller.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.ZeroAddress.selector);
        almCore.recordRedeemRequest(address(0), owner_, owner_, shares);
    }

    function testFuzz_Revert_recordRedeemRequest_ZeroAmount(address controller) public {
        // Given: A controller that is neither the zero address nor the core.
        vm.assume(controller != address(0) && controller != address(almCore));

        // And: A vault forwarding a request for nothing.

        // When: It records it.
        // Then: It reverts, rather than recording an id no one can cancel.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.ZeroAmount.selector);
        almCore.recordRedeemRequest(controller, controller, controller, 0);
    }

    function testFuzz_Revert_recordRedeemRequest_PerUserCapExceeded(uint256 shares, address owner_) public {
        // Given: Any owner apart from the controller, and a per user cap a share short.
        vm.assume(owner_ != controller && owner_ != address(almCore) && owner_ != address(0));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(owner_, shares);
        vm.prank(factory);
        almCore.setPerUserCap(shares - 1);

        // When: The vault records a redeem for the controller from the owner.
        // Then: It reverts, the controller's cap balance rising past the cap.
        vm.prank(asyncVault0);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.recordRedeemRequest(controller, owner_, owner_, shares);
    }

    function testFuzz_Success_recordRedeemRequest_TakesCustodyOfTheShares(address controller, uint256 shares) public {
        // Given: A controller holding the shares, with the vault allowed to move them.
        vm.assume(controller != address(0) && controller != address(almCore));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The vault records the request.
        recordRedeemAt(asyncVault0, controller, shares);

        // Then: The core took custody, the record and the pending epoch hold the shares.
        assertEq(almCore.redeemRecord(asyncVault0, controller).epoch, 0);
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, shares);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, shares);
        assertEq(almCore.balanceOf(address(almCore)), shares);
        assertEq(almCore.balanceOf(controller), 0);

        // And: The controller's claimable shares do not move.
        assertEq(almCore.claimableSharesOf_(controller), 0);
    }

    function testFuzz_Success_recordRedeemRequest_AnOwnerItsOwnOperatorNeedsNoAllowance(uint256 shares) public {
        // Given: A controller holding shares, its own operator, without an allowance.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(controller, shares);
        vm.prank(asyncVault0);
        almCore.setOperator(controller, controller, true);

        // When: The vault records the controller's own request.
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(controller, controller, controller, shares);

        // Then: The core took custody of the shares.
        assertEq(almCore.balanceOf(address(almCore)), shares);
        assertEq(almCore.balanceOf(controller), 0);
    }

    function testFuzz_Success_recordRedeemRequest_MovesTheSharesToPending(uint256 shares) public {
        // Given: A per user cap of nothing.
        vm.prank(factory);
        almCore.setPerUserCap(0);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The controller redeems its own shares.
        recordRedeemAt(asyncVault0, controller, shares);

        // Then: The shares moved into its pending shares, unchecked.
        assertEq(almCore.pendingShares_(controller), shares);
        assertEq(almCore.balanceOf(controller), 0);
    }

    function testFuzz_Success_recordRedeemRequest_LeavesEscrowAlone(address controller, uint256 shares) public {
        // Given: A controller holding the shares, with the vault allowed to move them.
        vm.assume(controller != address(0) && controller != address(almCore));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: The vault records the request.
        recordRedeemAt(asyncVault0, controller, shares);

        // Then: No pool token was escrowed.
        uint256 escrowed0 = almCore.getEscrowed0();
        uint256 escrowed1 = almCore.getEscrowed1();
        assertEq(escrowed0, 0);
        assertEq(escrowed1, 0);
    }

    function testFuzz_Success_recordRedeemRequest_KeyedByController(address controller, address second, uint256 shares)
        public
    {
        // Given: Two controllers at the same vault.
        vm.assume(controller != second);
        vm.assume(controller != address(0) && controller != address(almCore));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Only the first has a request recorded.
        recordRedeemAt(asyncVault0, controller, shares);

        // Then: The record is the first's, and the second has none.
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, shares);
        assertEq(almCore.redeemRecord(asyncVault0, second).amountIn, 0);
    }

    function testFuzz_Success_recordRedeemRequest_CheckpointsTheOwnerAndTheCore(
        uint96 shares,
        uint96 earned,
        uint256 seedShares,
        uint256 pick
    ) public {
        // Given: No per user cap.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: An owner with the shares in its balance, the vault allowed to move them.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, shares);

        // And: An accrual not yet checkpointed, on a chain that mints.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        setMintableStatus(pick);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + shares);

        // When: The vault records a redeem for the controller from the owner.
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(controller, accountA, accountA, shares);

        // Then: The shares left the owner, the controller credited nothing.
        assertEq(almCore.balanceOf(accountA), 0);
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, shares);
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The owner and the core were checkpointed at the new reward per share.
        assertEq(almCore.getRewardSnapshot(accountA), rewardPerShare);
        assertEq(almCore.getProtocolRewardSnapshot(), rewardPerShare);
    }

    function testFuzz_Success_recordRedeemRequest_CountsTheGaugeOnAnyChainStatus(
        uint96 shares,
        uint96 earned,
        uint256 seedShares,
        uint48 windowEnd,
        uint256 status
    ) public {
        // Given: No per user cap.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: An owner with the shares in its balance, the vault allowed to move them.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, shares);

        // And: Emissions earned at the gauge and a window end, on a fuzzed chain status.
        mockEarned(gauge, address(almCore), earned);
        windowEnd = uint48(bound(windowEnd, 1, type(uint48).max));
        almCore.setWindowEnd(windowEnd);
        setAnyStatus(status);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + shares);

        // When: The vault records a redeem for the controller from the owner.
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(controller, accountA, accountA, shares);

        // Then: Reward per share and high water count the gauge on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare);
        assertEq(almCore.getRewardHighWater(), net);

        // And: The owner earned on its balance up to that reward per share.
        assertEq(almCore.getPendingReward(accountA), uint256(shares).fullMulDiv(rewardPerShare, 1e18));

        // And: The window end is folded.
        assertEq(almCore.getWindowEnd(), 0);
    }

    function testFuzz_Success_recordRedeemRequest_SecondRequestCreditsTheProtocol(
        uint96 first,
        uint96 shares,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: No per user cap.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A pending redeem record, and an owner with more shares for the controller.
        first = uint96(bound(first, 1, type(uint96).max));
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        recordRedeemAt(asyncVault0, controller, first);
        almCore.mintShares(accountA, shares);

        // And: An accrual not yet checkpointed.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + first + shares);

        // When: The vault records a second redeem for the controller in the same epoch.
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(controller, accountA, accountA, shares);

        // Then: The pending record's escrow earned for the protocol.
        assertEq(almCore.getProtocolFeesReward(), uint256(first).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getPendingReward(controller), 0);

        // And: The record and the pending epoch hold both requests.
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, uint256(first) + shares);
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountIn, uint256(first) + shares);
    }

    function testFuzz_Success_recordRedeemRequest_AccruesTheControllerThatIsTheOwnerOnItsBalance(
        uint96 balance,
        uint96 escrowed,
        uint96 shares,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A controller with a balance and escrowed shares, redeeming part of it.
        balance = uint96(bound(balance, 1, type(uint96).max));
        shares = uint96(bound(shares, 1, balance));
        seedShares = bound(
            seedShares, FixedPointMathLib.fullMulDivUp(type(uint96).max, 1e18, type(uint128).max) + 1, type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(controller, balance);
        almCore.mintShares(address(almCore), escrowed);
        almCore.setClaimableShares(controller, escrowed);

        // And: An accrual not yet checkpointed.
        earned = uint96(bound(earned, 1, type(uint96).max));
        mockEarned(gauge, address(almCore), earned);
        uint256 net = earned - uint256(earned) * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = net.fullMulDiv(1e18, seedShares + balance + escrowed);

        // When: The vault records a redeem for the controller from its own balance.
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(controller, controller, controller, shares);

        // Then: The shares moved from its balance into the record, its escrow unchanged.
        assertEq(almCore.balanceOf(controller), balance - shares);
        assertEq(almCore.redeemRecord(asyncVault0, controller).amountIn, shares);
        assertEq(almCore.claimableSharesOf_(controller), escrowed);

        // And: It was credited on its prior balance, the protocol on the escrow.
        assertEq(almCore.getPendingReward(controller), uint256(balance).fullMulDiv(rewardPerShare, 1e18));
        assertEq(almCore.getProtocolFeesReward(), uint256(escrowed).fullMulDiv(rewardPerShare, 1e18));
    }
}
