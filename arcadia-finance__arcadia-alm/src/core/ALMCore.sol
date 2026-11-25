/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { AsyncVaultGuard } from "./abstracts/mixins/AsyncVaultGuard.sol";
import { ConfigLib } from "./libraries/state/ConfigLib.sol";
import { CoreParameters } from "./types/CoreParameters.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC7575Share } from "./abstracts/tokens/ERC7575Share.sol";
import { Extsload } from "@uniswap/v4-core/src/Extsload.sol";
import { Exttload } from "@uniswap/v4-core/src/Exttload.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IBaseFactory } from "../interfaces/IBaseFactory.sol";
import { MetadataReaderLib } from "@solady/utils/MetadataReaderLib.sol";
import { PoolLogic } from "../shared/libraries/logic/PoolLogic.sol";
import { Queue, Record, State } from "./types/State.sol";
import { QueueLib } from "./libraries/state/QueueLib.sol";
import { Range } from "./types/Range.sol";
import { RangeAmounts } from "./types/RangeAmounts.sol";
import { RangesLib } from "./libraries/state/RangesLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { TokenDelta, TokenDeltaLib } from "./types/TokenDelta.sol";

/**
 * @title ALM Core.
 * @author Pragma Labs
 * @notice Holds one pool's ranges and buffer, and issues aLP shares against them.
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract ALMCore is ERC7575Share, AsyncVaultGuard, Extsload, Exttload {
    using FixedPointMathLib for uint256;
    using RangesLib for Range[];
    using SafeTransferLib for address;
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidController();
    error InvalidExtension();
    error NotInitialized();
    error OnlyPool();
    error OnlyVault();
    error Paused();
    error ZeroShares();

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() {
        CoreParameters memory params = IBaseFactory(msg.sender).parameters();
        if (KEEPER_EXTENSION.code.length == 0 || ADMIN_EXTENSION.code.length == 0) revert InvalidExtension();

        State storage state = _state();
        state.config.feeRecipient = params.feeRecipient;
        state.config.arbBlockNumber = params.arbBlockNumber;
        if (params.rewardToken == params.token0) state.config.rewardPoolToken = 1;
        else if (params.rewardToken == params.token1) state.config.rewardPoolToken = 2;
        TOKEN0.safeApproveWithRetry(POSITION_MANAGER, type(uint256).max);
        TOKEN1.safeApproveWithRetry(POSITION_MANAGER, type(uint256).max);

        string memory pair =
            string.concat(MetadataReaderLib.readSymbol(TOKEN0), "/", MetadataReaderLib.readSymbol(TOKEN1));
        state.share.name = string.concat("Arcadia ALM ", pair);
        state.share.symbol = string.concat("aLP-", pair);

        emit VaultUpdate(TOKEN0, SYNC_VAULT0);
        emit VaultUpdate(TOKEN1, SYNC_VAULT1);
        emit VaultsSet(SYNC_VAULT0, SYNC_VAULT1, ASYNC_VAULT0, ASYNC_VAULT1);
    }

    /* //////////////////////////////////////////////////////////////
                                 VAULTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets whether an operator may act for a controller.
     * param controller The account the operator acts for.
     * param operator The account approved to act on the controller's behalf.
     * param approved True to approve, false to revoke.
     * @return True on success.
     * @dev Only the core's sync and async vaults can call it.
     */
    function setOperator(address, address, bool) external returns (bool) {
        _delegateAdmin();
    }

    /* //////////////////////////////////////////////////////////////
                             ERC20 OVERRIDES
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC20
     */
    function transfer(address to, uint256 amount) public override returns (bool success) {
        if (to == address(0)) revert InvalidRecipient();
        success = super.transfer(to, amount);
        if (to != msg.sender) _state().checkPerUserCap(to, balanceOf(to));
    }

    /**
     * @inheritdoc ERC20
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool success) {
        if (to == address(0)) revert InvalidRecipient();
        success = super.transferFrom(from, to, amount);
        if (to != from) _state().checkPerUserCap(to, balanceOf(to));
    }

    /* //////////////////////////////////////////////////////////////
                           SYNCHRONOUS VAULT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Bootstraps the vault, once, before any mint.
     * param amount0 The token0 amount pulled into the buffer.
     * param amount1 The token1 amount pulled into the buffer.
     * param shares The aLP supply minted, of which DEAD_SHARES go to address(1).
     * param receiver The account the rest of the supply is minted to.
     */
    function seed(uint256, uint256, uint256, address) external {
        _delegateAdmin();
    }

    /**
     * @notice Mints aLP shares against a pro-rata payment in kind.
     * @param shares The aLP shares minted.
     * @param receiver The account the shares are minted to.
     * @return amount0 The token0 the caller pays.
     * @return amount1 The token1 the caller pays.
     * @dev Needs no maximums: spot must sit in the TWAP band and the caller's allowance caps the pull.
     */
    function mint(uint256 shares, address receiver) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        // Checks.
        State storage state = _state();
        if (receiver == address(0)) revert InvalidRecipient();
        if (shares == 0) revert ZeroShares();
        if (state.config.paused) revert Paused();
        uint256 supplyBefore = totalSupply();
        if (supplyBefore == 0) revert NotInitialized();
        state.checkTotalCap(supplyBefore + shares);
        // Unchecked: the receiver's balance is at most the supply.
        unchecked {
            state.checkPerUserCap(receiver, balanceOf(receiver) + shares);
        }
        uint160 sqrtPriceX96;
        uint128[] memory positionLiquidity;
        {
            sqrtPriceX96 = PoolLogic.sqrtPriceX96(POOL);
            state.config.checkTwapDeviation(POOL, sqrtPriceX96);

            // Price the shares.
            uint256 fees0;
            uint256 fees1;
            (fees0, fees1, positionLiquidity) = _getUnstakedPositions(state);
            amount0 = (state.poolTokens.buffer.amount0 + fees0).fullMulDivUp(shares, supplyBefore);
            amount1 = (state.poolTokens.buffer.amount1 + fees1).fullMulDivUp(shares, supplyBefore);
        }
        {
            (uint256 amount0Desired, uint256 amount1Desired, RangeAmounts[] memory mintAmounts) =
                state.ranges.getMintAmounts(positionLiquidity, sqrtPriceX96, shares, supplyBefore);

            // Pull the payment.
            {
                uint256 pulled = amount0 + amount0Desired;
                if (pulled > 0) TOKEN0.safeTransferFrom(msg.sender, address(this), pulled);
                pulled = amount1 + amount1Desired;
                if (pulled > 0) TOKEN1.safeTransferFrom(msg.sender, address(this), pulled);
            }
            state.poolTokens.buffer.applyDelta(TokenDeltaLib.fromAmounts(amount0, amount1));

            // Mint liquidity pro rata.
            (uint256 used0, uint256 used1) =
                TokenDeltaLib.toAmounts(state.addLiquidity(POSITION_MANAGER, mintAmounts).neg());

            // Refund unused token0, the position manager is expected to use amount1Desired in full.
            // Unchecked: the refund is below amount0Desired, and the amounts and the used amounts are below 2^127.
            unchecked {
                if (amount0Desired > used0) TOKEN0.safeTransfer(msg.sender, amount0Desired - used0);
                amount0 += used0;
                amount1 += used1;
            }
        }

        // Update State.
        _mint(receiver, shares);

        emit Mint(msg.sender, receiver, shares, amount0, amount1);
    }

    /**
     * @notice Burns aLP shares and releases their pro-rata claim in kind.
     * @param shares The aLP shares burned.
     * @param receiver The account the released tokens go to.
     * @param owner_ The account the shares are burned from.
     * @return amount0 The token0 released, rounded down.
     * @return amount1 The token1 released, rounded down.
     * @dev Burns take the unstaked side first, to not forfeit the emissions of a staked side inside its penalty window.
     * @dev Needs no price check or minimums: a burn at a moved price pays at least its value at the true price.
     */
    function burn(uint256 shares, address receiver, address owner_)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = _burn(shares, owner_, msg.sender);

        // Pay out the pool tokens.
        _payBurn(receiver, receiver, receiver, owner_, shares, amount0, amount1);
    }

    /**
     * @notice Burns aLP shares for a sync vault's caller and releases their pro-rata claim in kind.
     * @param shares The aLP shares burned.
     * @param receiver The account the vault's asset goes to, the other pool token going to the vault.
     * @param owner_ The account the shares are burned from.
     * @param caller The account that called the vault.
     * @return amount0 The token0 released, rounded down.
     * @return amount1 The token1 released, rounded down.
     */
    function trustedBurn(uint256 shares, address receiver, address owner_, address caller)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        bool isToken0 = msg.sender == SYNC_VAULT0;
        if (!isToken0 && msg.sender != SYNC_VAULT1) revert OnlyVault();
        (amount0, amount1) = _burn(shares, owner_, caller);

        // Pay out the vault's asset to the receiver and the other pool token to the vault.
        _payBurn(
            receiver,
            isToken0 ? receiver : msg.sender,
            isToken0 ? msg.sender : receiver,
            owner_,
            shares,
            amount0,
            amount1
        );
    }

    /**
     * @notice Pays out a burn's pool tokens.
     * @param receiver The receiver of the burn.
     * @param to0 The account token0 goes to.
     * @param to1 The account token1 goes to.
     * @param owner_ The account the shares were burned from.
     * @param shares The aLP shares burned.
     * @param amount0 The token0 released.
     * @param amount1 The token1 released.
     */
    function _payBurn(
        address receiver,
        address to0,
        address to1,
        address owner_,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    ) internal {
        TOKEN0.safeTransfer(to0, amount0);
        TOKEN1.safeTransfer(to1, amount1);

        emit Burn(msg.sender, receiver, owner_, shares, amount0, amount1);
    }

    /**
     * @notice Burns an owner's aLP shares, spending the caller's allowance unless it is the owner or its operator.
     * @param shares The aLP shares burned.
     * @param owner_ The account the shares are burned from.
     * @param caller The account acting for the owner.
     * @return amount0 The token0 released, rounded down.
     * @return amount1 The token1 released, rounded down.
     */
    function _burn(uint256 shares, address owner_, address caller) internal returns (uint256 amount0, uint256 amount1) {
        // Checks.
        State storage state = _state();
        _spendAllowanceUnlessOperator(state, owner_, caller, shares);

        // Cache supply.
        uint256 supplyBefore = totalSupply();
        if (supplyBefore == 0) revert NotInitialized();

        // Update State.
        _burn(owner_, shares);

        // Burn liquidity pro rata.
        TokenDelta fees;
        {
            TokenDelta principal;
            (principal, fees) = state.removeLiquidity(POSITION_MANAGER, GAUGE, GAUGE_FACTORY, shares, supplyBefore);

            // Receiver receives full amount of burned principal.
            (amount0, amount1) = TokenDeltaLib.toAmounts(principal);
        }

        {
            // From collected fees, subtract share for the protocol.
            TokenDelta protocolFee;
            uint256 netFees0;
            uint256 netFees1;
            {
                (uint256 fees0, uint256 fees1) = TokenDeltaLib.toAmounts(fees);
                uint256 bps = state.config.protocolSwapFeeBps;
                uint256 protocolFee0 = fees0.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR);
                uint256 protocolFee1 = fees1.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR);
                protocolFee = TokenDeltaLib.fromAmounts(protocolFee0, protocolFee1);

                // Calculate net collected fees.
                // Unchecked: the protocol fee is at most half of the collected fees.
                unchecked {
                    (netFees0, netFees1) = (fees0 - protocolFee0, fees1 - protocolFee1);
                }

                if ((fees0 | fees1) != 0) emit FeesCollected(fees0, fees1);
            }

            // Receiver receives its share of the buffer.
            uint256 fromBuffer0;
            uint256 fromBuffer1;
            // Unchecked: the buffer and the net fees are below 2^128.
            unchecked {
                fromBuffer0 = (state.poolTokens.buffer.amount0 + netFees0).fullMulDiv(shares, supplyBefore);
                fromBuffer1 = (state.poolTokens.buffer.amount1 + netFees1).fullMulDiv(shares, supplyBefore);
                amount0 += fromBuffer0;
                amount1 += fromBuffer1;
            }

            // Update State.
            state.poolTokens.protocolFees.applyDelta(protocolFee);
            state.poolTokens.buffer
                .applyDelta(
                    TokenDeltaLib.fromAmounts(netFees0, netFees1)
                        .add(TokenDeltaLib.fromAmounts(fromBuffer0, fromBuffer1).neg())
                );
        }
    }

    /**
     * @notice Spends the caller's allowance unless it is the owner or its operator.
     * @param state The core state.
     * @param owner_ The account the shares are taken from.
     * @param caller The account acting for the owner.
     * @param shares The aLP shares taken.
     */
    function _spendAllowanceUnlessOperator(State storage state, address owner_, address caller, uint256 shares)
        internal
    {
        if (caller != owner_ && !state.share.isOperator[owner_][caller]) {
            _spendAllowance(owner_, caller, shares);
        }
    }

    /* //////////////////////////////////////////////////////////////
                          ASYNCHRONOUS VAULTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Records assets the vault has already moved here as a pending deposit.
     * @param controller The account the request is held for.
     * @param assets The asset amount requested.
     * @dev The total cap is checked when the keeper settles the deposit epoch.
     */
    function recordDepositRequest(address controller, uint256 assets) external nonReentrant {
        // Checks.
        if (controller == address(this)) revert InvalidController();
        (, bool isToken0) = _requireAsyncVault(msg.sender);

        // Update State, the vault transferred the escrowed assets in before this call.
        State storage state = _state();
        state.requestDeposit(
            state.vaultQueues[msg.sender].deposits, controller, isToken0, assets, PoolLogic.sqrtPriceX96(POOL)
        );

        // Check that the controller's aLP, claimable and pending shares stay within the per user cap.
        state.checkPerUserCap(controller, balanceOf(controller));

        // Check that the balances cover the escrowed assets.
        state.checkSolvency(TOKEN0, TOKEN1);
    }

    /**
     * @notice Takes shares into escrow and records them as a pending redeem.
     * @param controller The account the request is held for.
     * @param owner_ The account the shares are taken from.
     * @param caller The account that called the vault.
     * @param shares The aLP shares requested.
     */
    function recordRedeemRequest(address controller, address owner_, address caller, uint256 shares)
        external
        nonReentrant
    {
        // Checks.
        if (controller == address(this)) revert InvalidController();
        _requireAsyncVault(msg.sender);
        State storage state = _state();
        _spendAllowanceUnlessOperator(state, owner_, caller, shares);

        // Transfer the owner's shares to the core's escrow.
        _transfer(owner_, address(this), shares);

        // Update State.
        state.requestRedeem(state.vaultQueues[msg.sender].redeems, controller, shares);

        // Check that the controller's aLP, claimable and pending shares stay within the per user cap.
        if (owner_ != controller) state.checkPerUserCap(controller, balanceOf(controller));
    }

    /**
     * @notice Reverses an unfilled deposit request and refunds it from escrow.
     * param requestId The request id, unused.
     * @param controller The account the request is held for.
     * @param receiver The account the assets are returned to.
     * @return assets The asset amount returned.
     */
    function cancelDepositRequest(uint256, address controller, address receiver)
        external
        nonReentrant
        returns (uint256 assets)
    {
        // Checks.
        (address asset, bool isToken0) = _requireAsyncVault(msg.sender);
        State storage state = _state();
        Queue storage deposits = state.vaultQueues[msg.sender].deposits;
        Record storage record = deposits.records[controller];
        assets = record.amountIn;
        QueueLib.requirePending(record.epoch, deposits.pendingEpoch, assets);

        // Update State.
        state.cancelDeposit(deposits, record, controller, isToken0);

        // Transfer the assets from escrow to the receiver.
        asset.safeTransfer(receiver, assets);
    }

    /**
     * @notice Reverses an unfilled redeem request and returns the shares it held.
     * param requestId The request id, unused.
     * @param controller The account the request is held for.
     * @param receiver The account the shares are returned to.
     * @return shares The aLP shares returned.
     */
    function cancelRedeemRequest(uint256, address controller, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        // Checks.
        _requireAsyncVault(msg.sender);
        State storage state = _state();
        Queue storage redeems = state.vaultQueues[msg.sender].redeems;
        Record storage record = redeems.records[controller];
        shares = record.amountIn;
        QueueLib.requirePending(record.epoch, redeems.pendingEpoch, shares);

        // Transfer the shares from escrow to the receiver.
        _transferFromEscrow(state, controller, receiver, shares);

        // Update State.
        state.cancelRedeem(redeems, record, controller);
    }

    /**
     * @notice Pays out part of a filled deposit's claim in aLP.
     * @param controller The account the request is held for.
     * @param assets The settled asset amount claimed.
     * @param maxShares The most aLP shares transferred.
     * @param receiver The account the shares go to.
     * @return shares The aLP shares transferred.
     */
    function claimDepositRequest(address controller, uint256 assets, uint256 maxShares, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        // Checks.
        _requireAsyncVault(msg.sender);

        // Remove the claimed shares from the controller's claimable shares.
        State storage state = _state();
        shares = state.claimDeposit(state.vaultQueues[msg.sender].deposits, controller, assets, maxShares);

        // Transfer the shares from escrow to the receiver.
        _transferFromEscrow(state, controller, receiver, shares);
    }

    /**
     * @notice Pays out part of a filled redeem's claim from escrow.
     * @param controller The account the request is held for.
     * @param shares The settled aLP shares claimed.
     * @param maxAssets The most assets transferred.
     * @param receiver The account the assets go to.
     * @return assets The asset amount transferred.
     */
    function claimRedeemRequest(address controller, uint256 shares, uint256 maxAssets, address receiver)
        external
        nonReentrant
        returns (uint256 assets)
    {
        // Checks.
        (address asset, bool isToken0) = _requireAsyncVault(msg.sender);

        // Update State.
        State storage state = _state();
        assets = state.claimRedeem(state.vaultQueues[msg.sender].redeems, controller, isToken0, shares, maxAssets);

        // Transfer the assets from escrow to the receiver.
        asset.safeTransfer(receiver, assets);
    }

    /**
     * @notice Transfers shares from escrow to a receiver.
     * @param state The core state.
     * @param controller The account the request is held for.
     * @param receiver The account the shares go to.
     * @param shares The aLP shares transferred.
     */
    function _transferFromEscrow(State storage state, address controller, address receiver, uint256 shares) internal {
        // Check that the receiver's aLP, claimable and pending shares stay within the per user cap.
        // Unchecked: the balance and the shares are within the uint128 total cap.
        unchecked {
            if (receiver != controller) state.checkPerUserCap(receiver, balanceOf(receiver) + shares);
        }

        // Transfer the shares from escrow to the receiver.
        _transfer(address(this), receiver, shares);
    }

    /* //////////////////////////////////////////////////////////////
                              KEEPER ACTION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Runs one keeper plan, bounded by the price it was computed against and by its shortfall at that price.
     * param commands One byte per step, each an opcode.
     * param inputs The tight-packed payload of each step.
     * param trustedSqrtPriceX96 The sqrt price the plan was computed against.
     */
    function execute(bytes calldata, bytes[] calldata, uint160) external {
        _delegate(KEEPER_EXTENSION);
    }

    /**
     * @notice Accrues the reward token received since the last interaction.
     * @dev Only the core itself can call it, which is how the extensions reach the core's own checkpoint.
     */
    function checkpoint() external {
        if (msg.sender != address(this)) revert Unauthorized();
        _checkpoint();
    }

    /* //////////////////////////////////////////////////////////////
                                INVENTORY
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accrues the untracked pool tokens to the protocol.
     * @return The token0 skimmed.
     * @return The token1 skimmed.
     */
    function skim() external returns (uint256, uint256) {
        _delegateAdmin();
    }

    /* //////////////////////////////////////////////////////////////
                               GOVERNANCE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the maximum number of ranges.
     * param newRangeCap The new range cap.
     */
    function setRangeCap(uint8) external {
        _delegateAdmin();
    }

    /**
     * @notice Sets the most aLP any one account may hold, counting its requests.
     * param newPerUserCap The new per user cap.
     */
    function setPerUserCap(uint256) external {
        _delegateAdmin();
    }

    /**
     * @notice Lowers the most aLP any one account may hold, counting its requests.
     * param newPerUserCap The new per user cap.
     */
    function lowerPerUserCap(uint256) external {
        _delegateAdmin();
    }

    /**
     * @notice Exempts an account from the per user cap, or lifts the exemption.
     * param account The account.
     * param exempt True to exempt, false to lift the exemption.
     */
    function setCapExempt(address, bool) external {
        _delegateAdmin();
    }

    /**
     * @notice Sets the maximum aLP supply.
     * param newTotalCap The new total cap.
     */
    function setTotalCap(uint256) external {
        _delegateAdmin();
    }

    /**
     * @notice Lowers the maximum aLP supply.
     * param newTotalCap The new total cap.
     */
    function lowerTotalCap(uint256) external {
        _delegateAdmin();
    }

    /**
     * @notice Sets the max shortfall per plan, the max swap cost and the minimum time between plans.
     * param newMaxShortfallBps The value per share a plan may lose against its trusted price.
     * param newMaxSwapCostBps The value a swap may lose against the pool's spot price at the start of its plan.
     * param newMinPlanInterval The minimum time between two plans, in seconds.
     */
    function setPlanLimits(uint16, uint16, uint32) external {
        _delegateAdmin();
    }

    /**
     * @notice Blocks minting and the keeper steps that add liquidity, swap or settle deposits.
     */
    function pause() external {
        _delegateAdmin();
    }

    /**
     * @notice Lifts the pause.
     */
    function unpause() external {
        _delegateAdmin();
    }

    /**
     * @notice Sets the TWAP reference window and the three price bands.
     * param newTwapWindow The TWAP window in seconds.
     * param newMaxSpotFromTwap The 1e18-scaled ratio band of the spot sqrt price around the TWAP.
     * param newMaxSpotFromTrusted The 1e18-scaled ratio band of the spot sqrt price around a plan's price.
     * param newMaxTwapFromTrusted The 1e18-scaled ratio band of the TWAP sqrt price around a plan's price.
     */
    function setDeviation(uint32, uint256, uint256, uint256) external {
        _delegateAdmin();
    }

    /**
     * @notice Sets both protocol fees and their recipient.
     * param newProtocolEmissionFeeBps The protocol share of claimed emissions.
     * param newProtocolSwapFeeBps The protocol share of collected swap fees.
     * param newFeeRecipient The recipient of the protocol fees.
     */
    function setProtocolFees(uint16, uint16, address) external {
        _delegateAdmin();
    }

    /**
     * @notice Pays the protocol fees accrued on both pool tokens and on the reward token out.
     * @return The token0 paid.
     * @return The token1 paid.
     * @return The reward token paid.
     */
    function payProtocolFees() external returns (uint256, uint256, uint256) {
        _delegateAdmin();
    }

    /* //////////////////////////////////////////////////////////////
                                 REWARDS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Pays out the emissions credited to an account.
     * param account The account whose reward is credited and paid.
     * @return The amount of reward token transferred.
     */
    function claimEmissions(address) external returns (uint256) {
        _delegateAdmin();
    }

    /**
     * @notice The emissions a holder is owed at this block, credited or not.
     * param account The holder, not the core.
     * @return The reward token owed.
     */
    function getRewardOwed(address) external returns (uint256) {
        _delegateAdmin();
    }

    /* //////////////////////////////////////////////////////////////
                               DELEGATION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Delegates the call to an extension with the immutables as ERC-3448 metadata, and returns its result.
     * @param extension The extension.
     */
    function _delegate(address extension) internal {
        int256 tickSpacing = TICK_SPACING;
        uint256 pool = uint160(POOL);
        uint256 token0 = uint160(TOKEN0);
        uint256 token1 = uint160(TOKEN1);
        uint256 gauge = uint160(GAUGE);
        uint256 asyncVault0 = uint160(ASYNC_VAULT0);
        uint256 asyncVault1 = uint160(ASYNC_VAULT1);
        uint256 syncVault0 = uint160(SYNC_VAULT0);
        uint256 syncVault1 = uint160(SYNC_VAULT1);
        assembly {
            let size := calldatasize()
            calldatacopy(0, 0, size)
            mstore(size, tickSpacing)
            mstore(add(size, 0x20), pool)
            mstore(add(size, 0x40), token0)
            mstore(add(size, 0x60), token1)
            mstore(add(size, 0x80), gauge)
            mstore(add(size, 0xa0), asyncVault0)
            mstore(add(size, 0xc0), asyncVault1)
            mstore(add(size, 0xe0), syncVault0)
            mstore(add(size, 0x100), syncVault1)
            mstore(add(size, 0x120), 0x120)
            let success := delegatecall(gas(), extension, 0, add(size, 0x140), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }

    /**
     * @notice Delegates the call to the admin extension.
     */
    function _delegateAdmin() internal {
        _delegate(ADMIN_EXTENSION);
    }

    /* //////////////////////////////////////////////////////////////
                              SWAP CALLBACK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Pays the pool the input of a swap this contract started.
     * @param amount0Delta The token0 the pool is owed, negative when the pool owes it.
     * @param amount1Delta The token1 the pool is owed, negative when the pool owes it.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (msg.sender != POOL) revert OnlyPool();

        if (amount0Delta > 0) TOKEN0.safeTransfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) TOKEN1.safeTransfer(msg.sender, uint256(amount1Delta));
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The unstaked sides' liquidity and their uncollected fees, net of the protocol share.
     * @return fees0 The token0 fees.
     * @return fees1 The token1 fees.
     * @return positionLiquidity Every unstaked side's liquidity.
     */
    function getUnstakedPositions()
        external
        view
        returns (uint256 fees0, uint256 fees1, uint128[] memory positionLiquidity)
    {
        _requireUnlocked();

        (fees0, fees1, positionLiquidity) = _getUnstakedPositions(_state());
    }

    /**
     * @notice The unstaked sides' liquidity and their uncollected fees, net of the protocol share.
     * @param state The core state.
     * @return fees0 The token0 fees.
     * @return fees1 The token1 fees.
     * @return positionLiquidity Every unstaked side's liquidity.
     */
    function _getUnstakedPositions(State storage state)
        internal
        view
        returns (uint256 fees0, uint256 fees1, uint128[] memory positionLiquidity)
    {
        (fees0, fees1, positionLiquidity) =
            state.ranges.getUnstakedPositions(state.config.protocolSwapFeeBps, POOL, POSITION_MANAGER);
    }

    /* //////////////////////////////////////////////////////////////
                             ERC721 RECEIVER
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accepts a position NFT sent by the position manager.
     * @return selector The ERC-721 receiver selector.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4 selector) {
        if (msg.sender != POSITION_MANAGER) revert Unauthorized();
        selector = this.onERC721Received.selector;
    }

    /* ///////////////////////////////////////////////////////////////
                          NATIVE ETH HANDLER
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Receives native ether.
     * @dev Accepts the position manager's ether refund on mints to prevent griefing, and is not meant for sending ether.
     */
    receive() external payable { }
}
