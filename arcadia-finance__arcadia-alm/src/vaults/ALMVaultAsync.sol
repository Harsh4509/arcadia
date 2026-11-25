/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../core/libraries/logic/ALMCoreViewLogic.sol";
import { BaseVault } from "./abstracts/base/BaseVault.sol";
import { BaseVaultAccounting } from "./abstracts/base/BaseVaultAccounting.sol";
import { ERC7540Deposit } from "./abstracts/tokens/ERC7540Deposit.sol";
import { ERC7540Operator } from "./abstracts/tokens/ERC7540Operator.sol";
import { ERC7540Redeem } from "./abstracts/tokens/ERC7540Redeem.sol";
import { IALMCore } from "../interfaces/IALMCore.sol";
import { QueueLib } from "../core/libraries/state/QueueLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

/**
 * @title ALM Vault Async.
 * @author Pragma Labs
 * @notice Queues one pool token for a keeper to settle, and hands back what a settlement left claimable.
 */
// forge-lint: disable-next-item(arbitrary-send-erc20, reentrancy-events, unused-return)
contract ALMVaultAsync is BaseVault, BaseVaultAccounting, ERC7540Deposit, ERC7540Redeem {
    using ALMCoreViewLogic for IALMCore;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                               PARAMETERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _core() internal view override returns (IALMCore core) {
        core = ALM_CORE;
    }

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _pool() internal view override returns (address pool) {
        pool = POOL;
    }

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _vault() internal view override returns (address vault) {
        vault = address(this);
    }

    /**
     * @inheritdoc BaseVaultAccounting
     */
    function _assetIsToken0() internal view override returns (bool assetIsToken0) {
        assetIsToken0 = ASSET_IS_TOKEN0;
    }

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event DepositRequestCanceled(
        address indexed controller, uint256 indexed requestId, address receiver, uint256 assets
    );
    event RedeemRequestCanceled(
        address indexed controller, uint256 indexed requestId, address receiver, uint256 shares
    );

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error InsufficientClaimable();

    /* //////////////////////////////////////////////////////////////
                                REQUESTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Queues an asset amount for a keeper to settle into aLP shares.
     * @param assets The asset amount queued.
     * @param controller The account the request is held for.
     * @param owner The account the assets are taken from.
     * @return The request id, 0.
     */
    function requestDeposit(uint256 assets, address controller, address owner)
        external
        whenNotPaused
        returns (uint256)
    {
        // Checks.
        _requireOperatorOrSelf(owner);

        // Pull the payment from the owner into the core.
        ASSET.safeTransferFrom(owner, address(ALM_CORE), assets);

        // Core records the payment as a pending deposit of the controller.
        ALM_CORE.recordDepositRequest(controller, assets);

        emit DepositRequest(controller, owner, 0, msg.sender, assets);
        return 0;
    }

    /**
     * @notice Queues aLP shares for a keeper to settle into the asset.
     * @param shares The aLP shares queued.
     * @param controller The account the request is held for.
     * @param owner The account the shares are taken from.
     * @return The request id, 0.
     */
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256) {
        // Pull the owner's shares into escrow as a pending redeem of the controller.
        ALM_CORE.recordRedeemRequest(controller, owner, msg.sender, shares);

        emit RedeemRequest(controller, owner, 0, msg.sender, shares);
        return 0;
    }

    /**
     * @notice Takes back a deposit request the keeper has not filled.
     * @param requestId The request id, unused.
     * @param controller The account the request is held for.
     * @param receiver The account the assets are returned to.
     * @return assets The asset amount returned.
     * @dev A one-step cancel that pays back in the same call, not the two-step flow of ERC-7887.
     */
    function cancelDepositRequest(uint256 requestId, address controller, address receiver)
        external
        returns (uint256 assets)
    {
        // Checks.
        _requireOperatorOrSelf(controller);

        // Transfer the pending assets of the controller to the receiver.
        assets = ALM_CORE.cancelDepositRequest(requestId, controller, receiver);

        emit DepositRequestCanceled(controller, 0, receiver, assets);
    }

    /**
     * @notice Takes back a redeem request the keeper has not filled.
     * @param requestId The request id, unused.
     * @param controller The account the request is held for.
     * @param receiver The account the shares are returned to.
     * @return shares The aLP shares returned.
     * @dev A one-step cancel that pays back in the same call, not the two-step flow of ERC-7887.
     */
    function cancelRedeemRequest(uint256 requestId, address controller, address receiver)
        external
        returns (uint256 shares)
    {
        // Checks.
        _requireOperatorOrSelf(controller);

        // Transfer the pending shares of the controller to the receiver.
        shares = ALM_CORE.cancelRedeemRequest(requestId, controller, receiver);

        emit RedeemRequestCanceled(controller, 0, receiver, shares);
    }

    /* //////////////////////////////////////////////////////////////
                                 CLAIMS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Claims aLP shares from a settled deposit, for the given asset amount.
     * @param assets The settled asset amount claimed.
     * @param receiver The account the shares go to.
     * @return shares The aLP shares claimed.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        // Transfer the claimed shares to the receiver, with the caller as controller.
        shares = deposit(assets, receiver, msg.sender);
    }

    /**
     * @notice Claims aLP shares from a settled deposit, for the given asset amount.
     * @param assets The settled asset amount claimed.
     * @param receiver The account the shares go to.
     * @param controller The account the request is held for.
     * @return shares The aLP shares claimed.
     */
    function deposit(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
        // Checks.
        _requireOperatorOrSelf(controller);

        // Transfer the claimed shares to the receiver.
        shares = _deposit(assets, type(uint256).max, receiver, controller);
    }

    /**
     * @notice Claims an exact amount of aLP shares from a settled deposit.
     * @param shares The aLP shares claimed.
     * @param receiver The account the shares go to.
     * @return assets The settled asset amount it claimed against.
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        // Transfer the claimed shares to the receiver, with the caller as controller.
        assets = mint(shares, receiver, msg.sender);
    }

    /**
     * @notice Claims an exact amount of aLP shares from a settled deposit.
     * @param shares The aLP shares claimed.
     * @param receiver The account the shares go to.
     * @param controller The account the request is held for.
     * @return assets The settled asset amount it claimed against.
     */
    function mint(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        // Checks.
        _requireOperatorOrSelf(controller);

        // Get the controller's claimable assets and shares.
        (uint256 claimableAssets, uint256 claimableShares) = _claimableDeposit(controller);

        // Checks.
        if (claimableShares == 0 || shares > claimableShares) revert InsufficientClaimable();

        // Calculate the settled assets the shares are claimed against.
        assets = QueueLib.requestAmountIn(shares, claimableAssets, claimableShares);

        // Transfer the claimed shares to the receiver.
        _deposit(assets, shares, receiver, controller);
    }

    /**
     * @notice Claims assets from a settled redeem, for the given aLP shares.
     * @param shares The settled aLP shares claimed.
     * @param receiver The account the assets go to.
     * @param controller The account the request is held for.
     * @return assets The asset amount claimed.
     */
    function redeem(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        // Checks.
        _requireOperatorOrSelf(controller);

        // Transfer the claimed assets to the receiver.
        assets = _redeem(shares, type(uint256).max, receiver, controller);
    }

    /**
     * @notice Claims an exact asset amount a settled redeem left.
     * @param assets The asset amount claimed.
     * @param receiver The account the assets go to.
     * @param controller The account the request is held for.
     * @return shares The settled aLP shares it claimed against.
     */
    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares) {
        // Checks.
        _requireOperatorOrSelf(controller);

        // Get the controller's claimable shares and assets.
        (uint256 claimableAssets, uint256 claimableShares) = _claimableRedeem(controller);

        // Checks.
        if (claimableAssets == 0 || assets > claimableAssets) revert InsufficientClaimable();

        // Calculate the settled shares the assets are claimed against.
        shares = QueueLib.requestAmountIn(assets, claimableShares, claimableAssets);

        // Transfer the claimed assets to the receiver.
        _redeem(shares, assets, receiver, controller);
    }

    /**
     * @notice Claims aLP shares from a settled deposit, for a controller already checked.
     * @param assets The settled asset amount claimed.
     * @param maxShares The most aLP shares claimed.
     * @param receiver The account the shares go to.
     * @param controller The account the request is held for.
     * @return shares The aLP shares claimed.
     */
    function _deposit(uint256 assets, uint256 maxShares, address receiver, address controller)
        internal
        returns (uint256 shares)
    {
        // Transfer the claimed shares from escrow to the receiver.
        shares = ALM_CORE.claimDepositRequest(controller, assets, maxShares, receiver);

        emit Deposit(controller, receiver, assets, shares);
    }

    /**
     * @notice Claims assets from a settled redeem, for a controller already checked.
     * @param shares The settled aLP shares claimed.
     * @param maxAssets The most assets claimed.
     * @param receiver The account the assets go to.
     * @param controller The account the request is held for.
     * @return assets The asset amount claimed.
     */
    function _redeem(uint256 shares, uint256 maxAssets, address receiver, address controller)
        internal
        returns (uint256 assets)
    {
        // Transfer the claimed assets from escrow to the receiver.
        assets = ALM_CORE.claimRedeemRequest(controller, shares, maxAssets, receiver);

        emit Withdraw(controller, receiver, controller, assets, shares);
    }

    /* //////////////////////////////////////////////////////////////
                              REQUEST VIEWS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The asset amount a deposit request still holds, before a keeper has settled it.
     * param requestId The request id, unused.
     * @param controller The account the request is held for.
     * @return assets The asset amount.
     */
    function pendingDepositRequest(uint256, address controller) external view override returns (uint256 assets) {
        assets = ALM_CORE.getPendingDeposit(address(this), controller);
    }

    /**
     * @notice The settled asset amount a controller may still claim shares against.
     * param requestId The request id, unused.
     * @param controller The account the requests are held for.
     * @return assets The asset amount.
     */
    function claimableDepositRequest(uint256, address controller) external view override returns (uint256 assets) {
        (assets,) = _claimableDeposit(controller);
    }

    /**
     * @notice The aLP shares a redeem request still holds, before a keeper has settled it.
     * param requestId The request id, unused.
     * @param controller The account the request is held for.
     * @return shares The aLP shares.
     */
    function pendingRedeemRequest(uint256, address controller) external view override returns (uint256 shares) {
        shares = ALM_CORE.getPendingRedeem(address(this), controller);
    }

    /**
     * @notice The settled aLP shares a controller may still claim assets against.
     * param requestId The request id, unused.
     * @param controller The account the requests are held for.
     * @return shares The aLP shares.
     */
    function claimableRedeemRequest(uint256, address controller) external view override returns (uint256 shares) {
        (, shares) = _claimableRedeem(controller);
    }

    /**
     * @notice What a controller's settled deposits left to claim on this vault.
     * @param controller The account the requests are held for.
     * @return assets The settled asset amount the share is claimed against.
     * @return shares The aLP shares left to claim.
     */
    function _claimableDeposit(address controller) internal view returns (uint256 assets, uint256 shares) {
        (assets, shares) = ALM_CORE.getClaimableDeposit(address(this), controller);
    }

    /**
     * @notice What a controller's settled redeems left to claim on this vault.
     * @param controller The account the requests are held for.
     * @return assets The asset amount left to claim.
     * @return shares The settled aLP shares the asset is claimed against.
     */
    function _claimableRedeem(address controller) internal view returns (uint256 assets, uint256 shares) {
        (assets, shares) = ALM_CORE.getClaimableRedeem(address(this), controller);
    }

    /* //////////////////////////////////////////////////////////////
                                  LIMITS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The settled asset amount a controller may claim shares against.
     * @param controller The account the requests are held for.
     * @return assets The asset amount.
     */
    function maxDeposit(address controller) external view returns (uint256 assets) {
        (assets,) = _claimableDeposit(controller);
    }

    /**
     * @notice The aLP a controller may claim.
     * @param controller The account the requests are held for.
     * @return shares The aLP shares.
     */
    function maxMint(address controller) external view returns (uint256 shares) {
        (, shares) = _claimableDeposit(controller);
    }

    /**
     * @notice The settled aLP shares a controller may claim assets against.
     * @param controller The account the requests are held for.
     * @return shares The aLP shares.
     */
    function maxRedeem(address controller) external view returns (uint256 shares) {
        (, shares) = _claimableRedeem(controller);
    }

    /**
     * @notice The asset amount a controller may claim.
     * @param controller The account the requests are held for.
     * @return assets The asset amount.
     */
    function maxWithdraw(address controller) external view returns (uint256 assets) {
        (assets,) = _claimableRedeem(controller);
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC7540Deposit
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC7540Deposit, ERC7540Redeem, ERC7540Operator)
        returns (bool supported)
    {
        supported = super.supportsInterface(interfaceId);
    }
}
