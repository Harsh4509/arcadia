/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Drives the creation, seeding, role and governance surface of "ALMFactory" for the invariant suite.
 */
// forge-lint: disable-next-item(calls-loop, unsafe-typecast, unused-return)
contract ALMFactoryHandler is BaseHandler {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contracts of a pool that are synchronous vaults.
    uint8 internal constant SYNC_VAULT_CONTRACTS =
        uint8((1 << Constants.CONTRACT_SYNC_VAULT0) | (1 << Constants.CONTRACT_SYNC_VAULT1));
    // The contracts of a pool that are asynchronous vaults.
    uint8 internal constant ASYNC_VAULT_CONTRACTS =
        uint8((1 << Constants.CONTRACT_ASYNC_VAULT0) | (1 << Constants.CONTRACT_ASYNC_VAULT1));
    // The contract of a pool that is its core.
    uint8 internal constant CORE_CONTRACT = uint8(1 << Constants.CONTRACT_CORE);
    // The governance forwarders of the factory.
    uint256 internal constant FORWARDERS = 9;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMFactory internal immutable FACTORY;
    address internal immutable FEE_RECIPIENT;
    uint32 internal immutable TWAP_WINDOW;

    address[] internal candidates;
    // The accounts roles rotate between and calls come from.
    address[] internal accounts;

    // The cores this handler saw created and configured.
    mapping(address core => bool configured) internal _configured;

    uint256 public ghostCreated;
    // The createCore and resumeCore reverts whose reason is not the one their arguments make expected.
    uint256 public ghostUnexpectedReverts;
    // The role-gated calls that went through from an account without the role.
    uint256 public ghostUnauthorizedAccepted;
    // The role-gated calls that went through, by kind.
    uint256 public ghostRoleMoves;
    uint256 public ghostKeeperMoves;
    uint256 public ghostPauseMoves;
    uint256 public ghostForwards;
    // The deployments out of order, a core before its vaults or a contract twice, that went through, and those tried.
    uint256 public ghostIllegalDeploymentsAccepted;
    uint256 public ghostIllegalDeploymentsTried;

    // The holder of each role, as the calls that went through set it.
    address public ghostAdmin;
    address public ghostGuardian;
    address public ghostSteward;
    mapping(address core => mapping(address keeper => bool approved)) public ghostIsKeeper;
    mapping(address core => bool paused) public ghostPaused;
    mapping(address core => uint256 shares) public ghostSeededShares;
    mapping(address core => address receiver) public ghostSeedReceiver;
    // The pools whose core went live.
    mapping(address pool => bool live) public ghostLive;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMFactory factory,
        address feeRecipient,
        uint32 twapWindow,
        address[] memory candidates_,
        address[] memory accounts_
    ) {
        FACTORY = factory;
        FEE_RECIPIENT = feeRecipient;
        TWAP_WINDOW = twapWindow;
        for (uint256 i; i < candidates_.length; ++i) {
            candidates.push(candidates_[i]);
        }
        for (uint256 i; i < accounts_.length; ++i) {
            accounts.push(accounts_[i]);
        }
        (ghostAdmin, ghostGuardian, ghostSteward) = (factory.admin(), factory.guardian(), factory.steward());
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function createCore(uint256 poolSeed, uint256 contractsSeed) external countCall(this.createCore.selector) {
        address pool = candidateAt(poolSeed);
        uint8 contracts = _creatable(0, contractsSeed);

        vm.prank(FACTORY.steward());
        try FACTORY.createCore(pool, FEE_RECIPIENT, _batchesFor(contracts)) {
            _afterCreation(pool);
        } catch (bytes memory reason) {
            _recordRevert(this.createCore.selector, reason);
            if (_selectorOf(reason) != ALMFactory.CoreExists.selector) ghostUnexpectedReverts++;
        }
    }

    function resumeCore(uint256 poolSeed, uint256 contractsSeed) external countCall(this.resumeCore.selector) {
        address pool = candidateAt(poolSeed);
        (uint8 contractsDeployed,) = FACTORY.pending(pool);
        uint8 contracts = _creatable(contractsDeployed, contractsSeed);

        vm.prank(FACTORY.steward());
        try FACTORY.resumeCore(pool, _batchesFor(contracts)) {
            _afterCreation(pool);
        } catch (bytes memory reason) {
            _recordRevert(this.resumeCore.selector, reason);
            if (_selectorOf(reason) != ALMFactory.PoolNotPending.selector) ghostUnexpectedReverts++;
        }
    }

    function resumeIllegally(uint256 poolSeed, bool redeploy) external countCall(this.resumeIllegally.selector) {
        address pool = candidateAt(poolSeed);
        (uint8 contractsDeployed, address feeRecipient) = FACTORY.pending(pool);
        if (feeRecipient == address(0)) return;
        if (!redeploy && contractsDeployed & Constants.CORE_DEPENDENCIES == Constants.CORE_DEPENDENCIES) return;
        uint8 contracts = CORE_CONTRACT;
        bytes4 expected = BaseFactory.ContractsMissing.selector;
        if (redeploy) {
            if (contractsDeployed == 0) return;
            contracts = contractsDeployed & (~contractsDeployed + 1);
            expected = BaseFactory.ContractExists.selector;
        }

        ghostIllegalDeploymentsTried++;
        vm.prank(FACTORY.steward());
        try FACTORY.resumeCore(pool, _batchesFor(contracts)) {
            ghostIllegalDeploymentsAccepted++;
            _afterCreation(pool);
        } catch (bytes memory reason) {
            _recordRevert(this.resumeIllegally.selector, reason);
            if (_selectorOf(reason) != expected) ghostUnexpectedReverts++;
        }
    }

    function seedCore(uint256 poolSeed, uint256 amount0, uint256 amount1, uint256 shares, address receiver)
        external
        countCall(this.seedCore.selector)
    {
        address core = FACTORY.getCore(candidateAt(poolSeed));
        if (core == address(0)) return;

        Vaults memory vaults = FACTORY.getVaults(core);
        ERC20Mock token0 = ERC20Mock(ALMVaultSync(vaults.syncVault0).asset());
        ERC20Mock token1 = ERC20Mock(ALMVaultSync(vaults.syncVault1).asset());
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, Constants.DEAD_SHARES + 1, type(uint128).max);
        address steward = FACTORY.steward();
        token0.mint(steward, amount0);
        token1.mint(steward, amount1);

        vm.startPrank(steward);
        token0.approve(address(FACTORY), amount0);
        token1.approve(address(FACTORY), amount1);
        try FACTORY.seedCore(core, amount0, amount1, shares, receiver) {
            (ghostSeededShares[core], ghostSeedReceiver[core]) = (shares, receiver);
        } catch (bytes memory reason) {
            _recordRevert(this.seedCore.selector, reason);
        }
        token0.approve(address(FACTORY), 0);
        token1.approve(address(FACTORY), 0);
        vm.stopPrank();
    }

    function setRole(uint256 roleSeed, uint256 accountSeed, uint256 callerSeed)
        external
        countCall(this.setRole.selector)
    {
        uint256 role = bound(roleSeed, 0, 2);
        address account = accountAt(accountSeed);
        address caller = accountAt(callerSeed);
        bytes memory data = role == 0
            ? abi.encodeCall(ALMFactory.setAdmin, (account))
            : role == 1
                ? abi.encodeCall(ALMFactory.setGuardian, (account))
                : abi.encodeCall(ALMFactory.setSteward, (account));
        bool authorized = caller == FACTORY.owner();

        vm.prank(caller);
        (bool success, bytes memory reason) = address(FACTORY).call(data);
        if (!success) return _recordRevert(this.setRole.selector, reason);
        ghostRoleMoves++;
        if (!authorized) ghostUnauthorizedAccepted++;
        if (role == 0) ghostAdmin = account;
        else if (role == 1) ghostGuardian = account;
        else ghostSteward = account;
    }

    function revokeGuardian(uint256 callerSeed) external countCall(this.revokeGuardian.selector) {
        address caller = accountAt(callerSeed);
        bool authorized = caller == FACTORY.steward();

        vm.prank(caller);
        try FACTORY.revokeGuardian() {
            ghostRoleMoves++;
            if (!authorized) ghostUnauthorizedAccepted++;
            ghostGuardian = address(0);
        } catch (bytes memory reason) {
            _recordRevert(this.revokeGuardian.selector, reason);
        }
    }

    function setKeeper(uint256 poolSeed, uint256 keeperSeed, uint256 callerSeed, bool add)
        external
        countCall(this.setKeeper.selector)
    {
        address core = FACTORY.getCore(candidateAt(poolSeed));
        address keeper = accountAt(keeperSeed);
        address caller = accountAt(callerSeed);
        bool authorized = add ? caller == FACTORY.admin() : _isGuardianOrSteward(caller);

        vm.prank(caller);
        (bool success, bytes memory reason) = address(FACTORY)
            .call(
                add
                    ? abi.encodeCall(ALMFactory.addKeeper, (core, keeper))
                    : abi.encodeCall(ALMFactory.removeKeeper, (core, keeper))
            );
        if (!success) return _recordRevert(this.setKeeper.selector, reason);
        ghostKeeperMoves++;
        if (!authorized) ghostUnauthorizedAccepted++;
        ghostIsKeeper[core][keeper] = add;
    }

    function setPaused(uint256 poolSeed, uint256 callerSeed, bool paused) external countCall(this.setPaused.selector) {
        address core = FACTORY.getCore(candidateAt(poolSeed));
        address caller = accountAt(callerSeed);
        bool authorized = paused ? _isGuardianOrSteward(caller) : caller == FACTORY.steward();

        vm.prank(caller);
        (bool success, bytes memory reason) = address(FACTORY)
            .call(paused ? abi.encodeCall(ALMFactory.pause, (core)) : abi.encodeCall(ALMFactory.unpause, (core)));
        if (!success) return _recordRevert(this.setPaused.selector, reason);
        ghostPauseMoves++;
        if (!authorized) ghostUnauthorizedAccepted++;
        ghostPaused[core] = paused;
    }

    function forward(uint256 poolSeed, uint256 callerSeed, uint256 pick, uint256 amount)
        external
        countCall(this.forward.selector)
    {
        address core = FACTORY.getCore(candidateAt(poolSeed));
        address caller = accountAt(callerSeed);
        pick = bound(pick, 0, FORWARDERS - 1);
        bool lowers = pick == 2 || pick == 5;
        bool authorized = lowers ? _isGuardianOrSteward(caller) : caller == FACTORY.admin();

        vm.prank(caller);
        (bool success, bytes memory reason) = address(FACTORY).call(_forwarderData(core, caller, pick, amount));
        if (!success) return _recordRevert(this.forward.selector, reason);
        ghostForwards++;
        if (!authorized) ghostUnauthorizedAccepted++;
    }

    /* //////////////////////////////////////////////////////////////
                                  VIEWS
    ////////////////////////////////////////////////////////////// */

    function candidateAt(uint256 seed) public view returns (address pool) {
        pool = candidates[bound(seed, 0, candidates.length - 1)];
    }

    function candidatesLength() external view returns (uint256 length) {
        length = candidates.length;
    }

    function accountAt(uint256 seed) public view returns (address account) {
        account = accounts[bound(seed, 0, accounts.length - 1)];
    }

    function accountsLength() external view returns (uint256 length) {
        length = accounts.length;
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _isGuardianOrSteward(address caller) internal view returns (bool holds) {
        holds = caller == FACTORY.guardian() || caller == FACTORY.steward();
    }

    function _forwarderData(address core, address account, uint256 pick, uint256 amount)
        internal
        view
        returns (bytes memory data)
    {
        if (pick == 0) {
            return abi.encodeCall(ALMFactory.setRangeCap, (core, uint8(bound(amount, 0, ConfigLib.MAX_RANGE_CAP))));
        }
        if (pick == 1) return abi.encodeCall(ALMFactory.setPerUserCap, (core, bound(amount, 0, type(uint128).max)));
        if (pick == 2) return abi.encodeCall(ALMFactory.lowerPerUserCap, (core, bound(amount, 0, type(uint128).max)));
        if (pick == 3) return abi.encodeCall(ALMFactory.setCapExempt, (core, account, amount % 2 == 0));
        if (pick == 4) return abi.encodeCall(ALMFactory.setTotalCap, (core, bound(amount, 0, type(uint128).max)));
        if (pick == 5) return abi.encodeCall(ALMFactory.lowerTotalCap, (core, bound(amount, 0, type(uint128).max)));
        if (pick == 6) {
            uint16 bps = uint16(bound(amount, 0, ConfigLib.BPS_DENOMINATOR));
            return abi.encodeCall(ALMFactory.setPlanLimits, (core, bps, bps, uint32(amount)));
        }
        if (pick == 7) {
            uint256 deviation = bound(amount, 0, type(uint64).max);
            return abi.encodeCall(ALMFactory.setDeviation, (core, TWAP_WINDOW, deviation, deviation, deviation));
        }
        uint16 fee = uint16(bound(amount, 0, ConfigLib.MAX_FEE_BPS));
        data = abi.encodeCall(ALMFactory.setProtocolFees, (core, fee, fee, FEE_RECIPIENT));
    }

    function _afterCreation(address pool) internal {
        address core = FACTORY.getCore(pool);
        if (core == address(0) || _configured[core]) return;
        _configured[core] = true;
        ghostLive[pool] = true;
        ghostCreated++;

        address admin = FACTORY.admin();
        vm.startPrank(admin);
        FACTORY.setDeviation(
            core, TWAP_WINDOW, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        FACTORY.setRangeCap(core, ConfigLib.MAX_RANGE_CAP);
        FACTORY.setTotalCap(core, type(uint128).max);
        FACTORY.setPerUserCap(core, type(uint128).max);
        vm.stopPrank();
    }

    function _creatable(uint8 contractsDeployed, uint256 contractsSeed) internal pure returns (uint8 contracts) {
        contracts =
            uint8(bound(contractsSeed, 0, Constants.ALL_CONTRACTS)) & Constants.ALL_CONTRACTS & ~contractsDeployed;
        if ((contractsDeployed | contracts) & Constants.CORE_DEPENDENCIES != Constants.CORE_DEPENDENCIES) {
            contracts &= ~CORE_CONTRACT;
        }
    }

    function _batchesFor(uint8 contracts) internal pure returns (Deployment[] memory deployments) {
        Deployment[] memory all = new Deployment[](3);
        uint256 count;
        if (contracts & SYNC_VAULT_CONTRACTS != 0) {
            all[count++] = Deployment(contracts & SYNC_VAULT_CONTRACTS, type(ALMVaultSync).creationCode);
        }
        if (contracts & ASYNC_VAULT_CONTRACTS != 0) {
            all[count++] = Deployment(contracts & ASYNC_VAULT_CONTRACTS, type(ALMVaultAsync).creationCode);
        }
        if (contracts & CORE_CONTRACT != 0) all[count++] = Deployment(CORE_CONTRACT, type(ALMCore).creationCode);

        deployments = new Deployment[](count);
        for (uint256 i; i < count; ++i) {
            deployments[i] = all[i];
        }
    }
}
