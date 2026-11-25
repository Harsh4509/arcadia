/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCore } from "../core/ALMCore.sol";
import { ALMVaultAsync } from "../vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../vaults/ALMVaultSync.sol";
import { BaseFactory } from "./abstracts/base/BaseFactory.sol";
import { CodeHashes } from "./types/CodeHashes.sol";
import { Deployment } from "./types/Deployment.sol";
import { IFactoryRegistry } from "../interfaces/IFactoryRegistry.sol";
import { IMetadexCLGauge } from "../interfaces/IMetadexCLGauge.sol";
import { IMetadexCLPool } from "../interfaces/IMetadexCLPool.sol";
import { Ownable } from "@solady/auth/Ownable.sol";
import { PendingCreation } from "./types/PendingCreation.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Vaults } from "../core/types/Vaults.sol";

/**
 * @title ALM Factory.
 * @author Pragma Labs
 * @notice Deploys a core and its four vaults, records which cores are genuine, and holds every governance role.
 */
// forge-lint: disable-next-item(missing-zero-check, reentrancy-events, unused-return)
contract ALMFactory is BaseFactory, Ownable {
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The fewest observations a pool's oracle must be set to hold.
    uint16 public constant MIN_OBSERVATION_CARDINALITY = 300;

    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    // Every parameter and every risk-increasing action.
    address public admin;
    // De-risking only, undelayed.
    address public guardian;
    // Creates and seeds cores, unpauses and revokes the guardian, undelayed.
    address public steward;
    // The core created for each pool.
    mapping(address pool => address core) public getCore;
    // The accounts that may run keeper plans on each core.
    mapping(address core => mapping(address keeper => bool approved)) public isKeeper;
    // The pool each core was created for.
    mapping(address core => address pool) public poolOf;
    // Every core, in creation order.
    address[] public allCores;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event AdminSet(address indexed admin);
    event CoreCreated(
        address indexed pool,
        address indexed core,
        address token0,
        address token1,
        address gauge,
        address feeRecipient,
        Vaults vaults
    );
    event GuardianSet(address indexed guardian);
    event KeeperSet(address indexed core, address indexed keeper, bool approved);
    event StewardSet(address indexed steward);

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error CoreExists();
    error CoreNotValid();
    error GaugeFactoryMismatch();
    error GaugeNotValid();
    error InvalidRecipient();
    error ObservationCardinalityTooLow();
    error PoolNotPending();
    error VoterMismatch();

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyAdmin() {
        _requireAdmin();
        _;
    }

    modifier onlyGuardianOrSteward() {
        _requireGuardianOrSteward();
        _;
    }

    modifier onlySteward() {
        _requireSteward();
        _;
    }

    modifier onlyCore(address core) {
        _requireCore(core);
        _;
    }

    /**
     * @notice Reverts unless the admin is calling.
     */
    function _requireAdmin() internal view {
        if (msg.sender != admin) revert Unauthorized();
    }

    /**
     * @notice Reverts unless the guardian or the steward is calling.
     */
    function _requireGuardianOrSteward() internal view {
        if (msg.sender != guardian && msg.sender != steward) revert Unauthorized();
    }

    /**
     * @notice Reverts unless the steward is calling.
     */
    function _requireSteward() internal view {
        if (msg.sender != steward) revert Unauthorized();
    }

    /**
     * @notice Reverts unless this factory created a core.
     * @param core The core.
     */
    function _requireCore(address core) internal view {
        if (!isCore(core)) revert CoreNotValid();
    }

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        address positionManager,
        address routerTrampoline,
        address leafVoter,
        address gaugeFactory,
        address rewardToken,
        bool arbBlockNumber,
        address owner_,
        CodeHashes memory codeHashes
    ) BaseFactory(positionManager, routerTrampoline, leafVoter, gaugeFactory, rewardToken, arbBlockNumber, codeHashes) {
        if (owner_ == address(0)) revert ZeroAddress();
        _initializeOwner(owner_);
    }

    /* //////////////////////////////////////////////////////////////
                                CREATION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Creates the extensions every pool shares.
     * @param deployments The creation code of each extension, with the extension it deploys.
     */
    function createExtensions(Deployment[] calldata deployments) external onlySteward {
        // Deploy the extensions named in the deployments.
        _deploy(address(0), deployments);
    }

    /**
     * @notice Starts the creation of a pool.
     * @param pool The Metadex CL pool.
     * @param feeRecipient The recipient of the protocol fees.
     * @param deployments The creation code of each kind, with the contracts it deploys.
     */
    function createCore(address pool, address feeRecipient, Deployment[] calldata deployments) external onlySteward {
        // Checks.
        if (getCore[pool] != address(0) || pending[pool].feeRecipient != address(0)) {
            revert CoreExists();
        }
        if (feeRecipient == address(0) || feeRecipient == computeAddress(pool, CONTRACT_CORE)) {
            revert InvalidRecipient();
        }

        // Cache the number of observations the pool's oracle is set to hold.
        (,,,, uint16 observationCardinalityNext,) = IMetadexCLPool(pool).slot0();

        // Checks.
        if (observationCardinalityNext < MIN_OBSERVATION_CARDINALITY) revert ObservationCardinalityTooLow();

        // Cache the gauge.
        address gauge = IMetadexCLPool(pool).gauge();

        // Checks.
        if (IFactoryRegistry(FACTORY_REGISTRY).gaugeToTarget(gauge) != pool) revert GaugeNotValid();
        if (IMetadexCLGauge(gauge).voter() != LEAF_VOTER) revert VoterMismatch();
        if (IMetadexCLGauge(gauge).gaugeFactory() != GAUGE_FACTORY) revert GaugeFactoryMismatch();

        // Update State.
        pending[pool] = PendingCreation({ feeRecipient: feeRecipient, contractsDeployed: 0 });

        // Deploy the contracts named in the deployments.
        _create(pool, deployments);
    }

    /**
     * @notice Continues the creation of a pool.
     * @param pool The Metadex CL pool.
     * @param deployments The creation code of each kind, with the contracts it deploys.
     */
    function resumeCore(address pool, Deployment[] calldata deployments) external onlySteward {
        // Checks.
        if (pending[pool].feeRecipient == address(0)) revert PoolNotPending();

        // Deploy the contracts named in the deployments.
        _create(pool, deployments);
    }

    /**
     * @notice Deploys the contracts the deployments name, and registers the pool's core and vaults once the core exists.
     * @param pool The Metadex CL pool.
     * @param deployments The creation code of each kind, with the contracts it deploys.
     */
    function _create(address pool, Deployment[] calldata deployments) internal {
        // Cache the fee recipient, the pending creation is deleted once the core is deployed.
        address feeRecipient = pending[pool].feeRecipient;

        // Deploy the contracts named in the deployments.
        address core = _deploy(pool, deployments);

        // If the core is not deployed yet, return.
        if (core == address(0)) return;

        // Update State.
        getCore[pool] = core;
        poolOf[core] = pool;
        allCores.push(core);

        emit CoreCreated(
            pool,
            core,
            IMetadexCLPool(pool).token0(),
            IMetadexCLPool(pool).token1(),
            IMetadexCLPool(pool).gauge(),
            feeRecipient,
            _vaults(pool)
        );
    }

    /**
     * @notice Bootstraps a core with the steward's own tokens.
     * @param core The core.
     * @param amount0 The token0 amount pulled into the buffer.
     * @param amount1 The token1 amount pulled into the buffer.
     * @param shares The aLP supply minted, of which DEAD_SHARES go to address(1).
     * @param receiver The account the rest of the supply is minted to.
     */
    function seedCore(address core, uint256 amount0, uint256 amount1, uint256 shares, address receiver)
        external
        onlySteward
        onlyCore(core)
    {
        // Cache the pool tokens.
        address pool = poolOf[core];
        address token0 = ALMVaultSync(computeAddress(pool, CONTRACT_SYNC_VAULT0)).asset();
        address token1 = ALMVaultSync(computeAddress(pool, CONTRACT_SYNC_VAULT1)).asset();

        // Pull the seed from the steward.
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        // Approve the core to pull the seed.
        token0.safeApproveWithRetry(core, amount0);
        token1.safeApproveWithRetry(core, amount1);

        // Seed the core (core pulls the seed into its buffer and mints the aLP supply).
        ALMCore(payable(core)).seed(amount0, amount1, shares, receiver);
    }

    /* //////////////////////////////////////////////////////////////
                                 ROLES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the admin.
     * @param newAdmin The new admin.
     */
    function setAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;

        emit AdminSet(newAdmin);
    }

    /**
     * @notice Sets the guardian.
     * @param newGuardian The new guardian.
     */
    function setGuardian(address newGuardian) external onlyOwner {
        guardian = newGuardian;

        emit GuardianSet(newGuardian);
    }

    /**
     * @notice Sets the steward.
     * @param newSteward The new steward.
     */
    function setSteward(address newSteward) external onlyOwner {
        steward = newSteward;

        emit StewardSet(newSteward);
    }

    /**
     * @notice Removes the guardian at once.
     */
    function revokeGuardian() external onlySteward {
        guardian = address(0);

        emit GuardianSet(address(0));
    }

    /**
     * @notice Lets an account run keeper plans on a core.
     * @param core The core.
     * @param keeper The keeper.
     */
    function addKeeper(address core, address keeper) external onlyAdmin onlyCore(core) {
        isKeeper[core][keeper] = true;

        emit KeeperSet(core, keeper, true);
    }

    /**
     * @notice Stops an account running keeper plans on a core.
     * @param core The core.
     * @param keeper The keeper.
     */
    function removeKeeper(address core, address keeper) external onlyGuardianOrSteward onlyCore(core) {
        isKeeper[core][keeper] = false;

        emit KeeperSet(core, keeper, false);
    }

    /* //////////////////////////////////////////////////////////////
                               GOVERNANCE
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets a core's maximum number of ranges.
     * @param core The core.
     * @param newRangeCap The new range cap.
     */
    function setRangeCap(address core, uint8 newRangeCap) external onlyAdmin onlyCore(core) {
        ALMCore(payable(core)).setRangeCap(newRangeCap);
    }

    /**
     * @notice Sets the most aLP any one account may hold in a core, counting its requests.
     * @param core The core.
     * @param newPerUserCap The new per user cap.
     */
    function setPerUserCap(address core, uint256 newPerUserCap) external onlyAdmin onlyCore(core) {
        ALMCore(payable(core)).setPerUserCap(newPerUserCap);
    }

    /**
     * @notice Lowers the most aLP any one account may hold in a core, counting its requests.
     * @param core The core.
     * @param newPerUserCap The new per user cap, below the current one.
     */
    function lowerPerUserCap(address core, uint256 newPerUserCap) external onlyGuardianOrSteward onlyCore(core) {
        ALMCore(payable(core)).lowerPerUserCap(newPerUserCap);
    }

    /**
     * @notice Exempts an account from a core's per user cap, or lifts the exemption.
     * @param core The core.
     * @param account The account.
     * @param exempt True to exempt, false to lift the exemption.
     */
    function setCapExempt(address core, address account, bool exempt) external onlyAdmin onlyCore(core) {
        ALMCore(payable(core)).setCapExempt(account, exempt);
    }

    /**
     * @notice Sets a core's maximum aLP supply, raising or lowering it.
     * @param core The core.
     * @param newTotalCap The new total cap.
     */
    function setTotalCap(address core, uint256 newTotalCap) external onlyAdmin onlyCore(core) {
        ALMCore(payable(core)).setTotalCap(newTotalCap);
    }

    /**
     * @notice Lowers a core's maximum aLP supply.
     * @param core The core.
     * @param newTotalCap The new total cap, below the current one.
     */
    function lowerTotalCap(address core, uint256 newTotalCap) external onlyGuardianOrSteward onlyCore(core) {
        ALMCore(payable(core)).lowerTotalCap(newTotalCap);
    }

    /**
     * @notice Sets a core's max shortfall per plan, max swap cost and minimum time between plans.
     * @param core The core.
     * @param newMaxShortfallBps The new bound, in basis points.
     * @param newMaxSwapCostBps The new swap cost bound, in basis points.
     * @param newMinPlanInterval The minimum time between two plans, in seconds.
     */
    function setPlanLimits(address core, uint16 newMaxShortfallBps, uint16 newMaxSwapCostBps, uint32 newMinPlanInterval)
        external
        onlyAdmin
        onlyCore(core)
    {
        ALMCore(payable(core)).setPlanLimits(newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    /**
     * @notice Sets a core's TWAP window and the bands its price is held to.
     * @param core The core.
     * @param newTwapWindow The TWAP window in seconds.
     * @param newMaxSpotFromTwap The 1e18-scaled ratio band of the spot sqrt price around the TWAP.
     * @param newMaxSpotFromTrusted The 1e18-scaled ratio band of the spot sqrt price around a plan's price.
     * @param newMaxTwapFromTrusted The 1e18-scaled ratio band of the TWAP sqrt price around a plan's price.
     * @dev A sqrt price band d is a price band of (1 + d)^2 - 1.
     */
    function setDeviation(
        address core,
        uint32 newTwapWindow,
        uint256 newMaxSpotFromTwap,
        uint256 newMaxSpotFromTrusted,
        uint256 newMaxTwapFromTrusted
    ) external onlyAdmin onlyCore(core) {
        ALMCore(payable(core))
            .setDeviation(newTwapWindow, newMaxSpotFromTwap, newMaxSpotFromTrusted, newMaxTwapFromTrusted);
    }

    /**
     * @notice Sets a core's protocol fees and their recipient.
     * @param core The core.
     * @param newProtocolEmissionFeeBps The protocol share of claimed emissions.
     * @param newProtocolSwapFeeBps The protocol share of collected swap fees.
     * @param newFeeRecipient The recipient of the protocol fees.
     */
    function setProtocolFees(
        address core,
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient
    ) external onlyAdmin onlyCore(core) {
        ALMCore(payable(core)).setProtocolFees(newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    /**
     * @notice Pauses a core and its four vaults.
     * @param core The core.
     */
    function pause(address core) external onlyGuardianOrSteward onlyCore(core) {
        // Cache the vaults of the core.
        Vaults memory vaults = _vaults(poolOf[core]);

        // Pause the core.
        ALMCore(payable(core)).pause();

        // Pause the four vaults.
        ALMVaultSync(vaults.syncVault0).setPaused(true);
        ALMVaultSync(vaults.syncVault1).setPaused(true);
        ALMVaultAsync(vaults.asyncVault0).setPaused(true);
        ALMVaultAsync(vaults.asyncVault1).setPaused(true);
    }

    /**
     * @notice Unpauses a core and its four vaults.
     * @param core The core.
     */
    function unpause(address core) external onlySteward onlyCore(core) {
        // Cache the vaults of the core.
        Vaults memory vaults = _vaults(poolOf[core]);

        // Unpause the core.
        ALMCore(payable(core)).unpause();

        // Unpause the four vaults.
        ALMVaultSync(vaults.syncVault0).setPaused(false);
        ALMVaultSync(vaults.syncVault1).setPaused(false);
        ALMVaultAsync(vaults.asyncVault0).setPaused(false);
        ALMVaultAsync(vaults.asyncVault1).setPaused(false);
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether a core was created by this factory.
     * @param core The core.
     * @return valid True when it was.
     */
    function isCore(address core) public view returns (bool valid) {
        valid = poolOf[core] != address(0);
    }

    /**
     * @notice The four vaults of a core.
     * @param core The core.
     * @return vaults The vaults, all zero when the core was not created here.
     */
    function getVaults(address core) external view returns (Vaults memory vaults) {
        if (isCore(core)) vaults = _vaults(poolOf[core]);
    }

    /**
     * @notice The number of cores created.
     * @return length The number of cores.
     */
    function allCoresLength() external view returns (uint256 length) {
        length = allCores.length;
    }
}
