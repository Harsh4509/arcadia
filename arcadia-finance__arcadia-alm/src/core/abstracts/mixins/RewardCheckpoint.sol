/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { BaseCore } from "../base/BaseCore.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC20Share } from "../tokens/ERC20Share.sol";
import { State } from "../../types/State.sol";

/**
 * @title Reward Checkpoint.
 * @author Pragma Labs
 * @notice The share token's emissions hook.
 */
abstract contract RewardCheckpoint is BaseCore, ERC20Share {
    /* //////////////////////////////////////////////////////////////
                               CHECKPOINT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accrues the reward token received since the last interaction.
     */
    function _checkpoint() internal virtual {
        _state().checkpoint(totalSupply(), REWARD_TOKEN, GAUGE, GAUGE_FACTORY, LEAF_VOTER);
    }

    /* //////////////////////////////////////////////////////////////
                             ERC20 OVERRIDES
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC20
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        _checkpoint();

        State storage state = _state();
        if (from != address(0)) state.accrueBalanceReward(from, balanceOf(from));
        if (to != address(0)) state.accrueBalanceReward(to, balanceOf(to));
    }
}
