/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Invariant_Test } from "./ALMCore.invariant.t.sol";
import { ERC20Mock } from "../utils/mocks/ERC20Mock.sol";

/**
 * @notice Invariant tests for contract "ALMCore" over a pool that pairs the reward token with another token.
 */
abstract contract ALMCore_RewardPoolToken_Invariant_Test is ALMCore_Invariant_Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // True when the reward token is token0, false when it is token1.
    bool internal immutable REWARD_IS_TOKEN0;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(bool rewardIsToken0) {
        REWARD_IS_TOKEN0 = rewardIsToken0;
    }

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function deployStack(bool root, PoolState memory poolState) internal override {
        poolState.rewardPoolToken = REWARD_IS_TOKEN0 ? 1 : 2;
        super.deployStack(root, poolState);
    }

    /* //////////////////////////////////////////////////////////////
                                 PROBES
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_probe_ARewardSideDonationAccruesAsReward(ProbeInputs memory inputs) public {
        // Given: A donation of the pool token that is the reward token.
        if (REWARD_IS_TOKEN0) donorHandler.donateToken0(inputs.amount0);
        else donorHandler.donateToken1(inputs.amount1);
        uint256 donated = REWARD_IS_TOKEN0 ? donorHandler.ghostDonated0() : donorHandler.ghostDonated1();

        // When: The core is skimmed.
        handler.skim();

        // Then: The skim went through and the donation counts as reward received.
        assertEq(handler.reverts(handler.skim.selector), 0);
        (uint256 received,,) = almCore.getRewardTotals();
        assertGe(received, donated);
        invariant_skimNeverBooksTheRewardTokenAsProtocolFees();
        invariant_rewardPoolTokenBalanceCoversTheReserveAndTheRewardBalance();
    }

    /* //////////////////////////////////////////////////////////////
                               INVARIANTS
    ////////////////////////////////////////////////////////////// */

    function invariant_token0BalanceEqualsBufferFeesEscrowAndUnskimmedDonations() public view override {
        if (REWARD_IS_TOKEN0) invariant_rewardPoolTokenBalanceCoversTheReserveAndTheRewardBalance();
        else super.invariant_token0BalanceEqualsBufferFeesEscrowAndUnskimmedDonations();
    }

    function invariant_token1BalanceEqualsBufferFeesEscrowAndUnskimmedDonations() public view override {
        if (REWARD_IS_TOKEN0) super.invariant_token1BalanceEqualsBufferFeesEscrowAndUnskimmedDonations();
        else invariant_rewardPoolTokenBalanceCoversTheReserveAndTheRewardBalance();
    }

    function invariant_rewardPoolTokenBalanceCoversTheReserveAndTheRewardBalance() public view {
        uint256 reserve = REWARD_IS_TOKEN0
            ? almCore.bufferAmount0() + almCore.getProtocolFees0() + almCore.getEscrowed0()
            : almCore.bufferAmount1() + almCore.getProtocolFees1() + almCore.getEscrowed1();

        assertGe(ERC20Mock(rewardToken).balanceOf(address(almCore)), reserve + almCore.getLastRewardBalance());
    }

    function invariant_skimNeverBooksTheRewardTokenAsProtocolFees() public view {
        assertEq(REWARD_IS_TOKEN0 ? handler.ghostSkimmed0() : handler.ghostSkimmed1(), 0);
    }
}

/**
 * @notice Invariant tests for contract "ALMCore" over a pool whose token0 is the reward token.
 */
contract ALMCore_RewardToken0_Invariant_Test is ALMCore_RewardPoolToken_Invariant_Test {
    constructor() ALMCore_RewardPoolToken_Invariant_Test(true) { }
}

/**
 * @notice Invariant tests for contract "ALMCore" over a pool whose token1 is the reward token.
 */
contract ALMCore_RewardToken1_Invariant_Test is ALMCore_RewardPoolToken_Invariant_Test {
    constructor() ALMCore_RewardPoolToken_Invariant_Test(false) { }
}
