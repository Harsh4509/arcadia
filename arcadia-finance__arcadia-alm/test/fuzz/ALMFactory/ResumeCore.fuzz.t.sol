/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Constants } from "../../utils/Constants.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { Errors } from "@openzeppelin/contracts/utils/Errors.sol";
import { IERC7540Deposit, IERC7540Redeem } from "@forge-std/interfaces/IERC7540.sol";
import { Ownable } from "@solady/auth/Ownable.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Fuzz tests for the function "resumeCore" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract ResumeCore_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_resumeCore_Unauthorized(PoolState memory poolState, address caller) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: The caller is not the steward.
        vm.assume(caller != users.steward);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: Calling resumeCore().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_Unauthorized_Role(PoolState memory poolState, uint256 pick) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: The caller holds another role than the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.steward);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: Calling resumeCore().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_PoolNotPending(PoolState memory poolState, address secondPool) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward resumes a creation that was never opened.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.PoolNotPending.selector);
        almFactory.resumeCore(secondPool, deployments);
    }

    function testFuzz_Revert_resumeCore_PoolNotPending_Created(PoolState memory poolState) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward resumes its creation.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.PoolNotPending.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_InvalidContracts_EmptyMask(PoolState memory poolState, bytes memory code)
        public
    {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: A deployment whose mask names no contract.
        Deployment[] memory deployments = new Deployment[](1);
        deployments[0] = Deployment(0, code);

        // When: The steward resumes the creation with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_InvalidContracts_TwoKinds(
        PoolState memory poolState,
        uint256 kind,
        uint256 offset,
        uint256 first,
        uint256 second,
        bytes memory code
    ) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: A deployment whose mask names two contracts of different kinds.
        kind = bound(kind, 0, 2);
        uint8 contract0 = contractOfKind(kind, first);
        uint8 contract1 = contractOfKind((kind + bound(offset, 1, 2)) % 3, second);
        Deployment[] memory deployments = new Deployment[](1);
        deployments[0] = Deployment(uint8(1 << contract0) | uint8(1 << contract1), code);

        // When: The steward resumes the creation with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_InvalidContracts_Extension(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: A deployment naming an extension, with its creation code.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_EXTENSION, Constants.CONTRACT_ADMIN_EXTENSION));
        Deployment[] memory deployments = deploymentsFor(uint8(1 << contract_), creationCodes());

        // When: The steward resumes the creation with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_CodeMismatch(PoolState memory poolState, uint8 contract_, bytes memory code)
        public
    {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: A deployment naming one contract with another kind's creation code.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_ASYNC_VAULT1 + 1));
        if (contract_ > Constants.CONTRACT_ASYNC_VAULT1) contract_ = Constants.CONTRACT_CORE;
        Deployment[] memory deployments = new Deployment[](1);
        deployments[0] = Deployment(uint8(1 << contract_), code);
        vm.assume(keccak256(code) != keccak256(deploymentsFor(uint8(1 << contract_), creationCodes())[0].creationCode));

        // When: The steward resumes the creation with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.CodeMismatch.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_ContractExists(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A creation opened with one contract that is not the core.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_ASYNC_VAULT1));
        Deployment[] memory deployments = deploymentsFor(uint8(1 << contract_), creationCodes());
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);

        // When: The steward resumes the creation with the same contract.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.ContractExists.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_ContractsMissing(PoolState memory poolState, uint8 deployed) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A creation opened with any strict subset of the contracts the core needs.
        deployed = uint8(bound(deployed, 0, Constants.CORE_DEPENDENCIES - 1));
        CreationCodes memory codes = creationCodes();
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deploymentsFor(deployed, codes));
        Deployment[] memory deployments = deploymentsFor(uint8(1 << Constants.CONTRACT_CORE), codes);

        // When: The steward resumes the creation with the core.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.ContractsMissing.selector);
        almFactory.resumeCore(address(pool), deployments);
    }

    function testFuzz_Revert_resumeCore_CreationRunsOutOfGas(
        PoolState memory poolState,
        uint8 contract_,
        uint256 gasLimit
    ) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: One vault of the creation.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_ASYNC_VAULT1));
        Deployment[] memory deployments = deploymentsFor(uint8(1 << contract_), creationCodes());

        // And: At most a warm resume's gas, short of the 64/63 its creation needs.
        uint256 used;
        for (uint256 i; i < 2; ++i) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(users.steward);
            almFactory.resumeCore(address(pool), deployments);
            used = vm.lastFrameGas().gasTotalUsed;
            vm.revertToState(snapshot);
        }
        gasLimit = bound(gasLimit, used / 2, used);

        // When: The steward resumes the creation with that gas.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(Errors.FailedDeployment.selector);
        almFactory.resumeCore{ gas: gasLimit }(address(pool), deployments);
    }

    function testFuzz_Success_resumeCore_MarksEachContractDone(PoolState memory poolState, uint8 first, uint8 second)
        public
    {
        // Given: A creation opened with any subset of the contracts but the core.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        first = uint8(bound(first, 0, Constants.CORE_DEPENDENCIES));
        CreationCodes memory codes = creationCodes();
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deploymentsFor(first, codes));
        second = uint8(bound(second, 0, Constants.CORE_DEPENDENCIES)) & ~first;

        // When: The steward resumes it with any subset of the rest but the core.
        vm.prank(users.steward);
        almFactory.resumeCore(address(pool), deploymentsFor(second, codes));

        // Then: The pending record marks every contract of both calls and the recipient.
        (uint8 contractsDeployed, address feeRecipient_) = almFactory.pending(address(pool));
        assertEq(contractsDeployed, first | second);
        assertEq(feeRecipient_, users.feeRecipient);
    }

    function testFuzz_Success_resumeCore_EveryContractAtItsAddress(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The steward creates the pool in its three transactions.
        setCoreCreated();

        // Then: Every contract of the pool has code at its kind's CREATE2 address.
        CreationCodes memory codes = creationCodes();
        for (uint8 contract_; contract_ <= Constants.CONTRACT_CORE; ++contract_) {
            if (uint8(1 << contract_) & Constants.EXTENSION_CONTRACTS != 0) continue;
            bytes memory code = deploymentsFor(uint8(1 << contract_), codes)[0].creationCode;
            address predicted = contractAddress(address(almFactory), address(pool), contract_, code);
            assertGt(predicted.code.length, 0);
            assertEq(almFactory.computeAddress(address(pool), contract_), predicted);
        }

        // And: The core and its vaults are registered at those addresses.
        assertEq(
            address(core), contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, codes.core)
        );
        assertEq(
            vaults.syncVault0,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault)
        );
        assertEq(
            vaults.syncVault1,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault)
        );
        assertEq(
            vaults.asyncVault0,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault)
        );
        assertEq(
            vaults.asyncVault1,
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        );
    }

    function testFuzz_Success_resumeCore_RegistersTheCoreOnItsStep(PoolState memory poolState) public {
        // Given: A factory with a pool's extensions and sync vaults created.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setSyncVaultsCreated();
        CreationCodes memory codes = creationCodes();
        address core_ = contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, codes.core);
        Vaults memory expected = Vaults(
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault),
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault),
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault),
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        );

        // When: The steward creates the asynchronous vaults and the core.
        // Then: The core is reported with the fee recipient of the first step.
        vm.expectEmit(address(almFactory));
        emit ALMFactory.CoreCreated(
            address(pool), core_, pool.token0(), pool.token1(), address(gauge), users.feeRecipient, expected
        );
        vm.prank(users.steward);
        almFactory.resumeCore(address(pool), asyncVaultAndCoreDeployments(codes));

        // Then: The pool resolves to the core, which is genuine, with its four vaults.
        assertEq(almFactory.getCore(address(pool)), core_);
        assertTrue(almFactory.isCore(core_));
        address[4] memory registered = vaultsOf(almFactory.getVaults(core_));
        address[4] memory list = vaultsOf(expected);
        for (uint256 i; i < 4; ++i) {
            assertEq(registered[i], list[i]);
        }

        // And: The pending record is deleted.
        (uint8 contractsDeployed, address feeRecipient_) = almFactory.pending(address(pool));
        assertEq(feeRecipient_, address(0));
        assertEq(contractsDeployed, 0);
    }

    function testFuzz_Success_resumeCore_NoCoreBeforeItsStep(PoolState memory poolState, uint8 deployed) public {
        // Given: A creation opened with the extensions.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();
        deployed = uint8(bound(deployed, 0, Constants.CORE_DEPENDENCIES));

        // When: The steward resumes it with any subset of the vaults.
        vm.prank(users.steward);
        almFactory.resumeCore(address(pool), deploymentsFor(deployed, creationCodes()));

        // Then: The pool has no core, and the address the core will take is not one.
        address core_ =
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, creationCodes().core);
        assertEq(almFactory.getCore(address(pool)), address(0));
        assertFalse(almFactory.isCore(core_));
    }

    function testFuzz_Success_resumeCore_VaultsUnusableBeforeTheCore(
        PoolState memory poolState,
        uint256 vaultPick,
        uint256 entry,
        uint256 amount,
        address caller
    ) public {
        // Given: A creation with all four vaults deployed and no core.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setSyncVaultsCreated();
        CreationCodes memory codes = creationCodes();
        vm.prank(users.steward);
        almFactory.resumeCore(
            address(pool),
            deploymentsFor(
                uint8((1 << Constants.CONTRACT_ASYNC_VAULT0) | (1 << Constants.CONTRACT_ASYNC_VAULT1)), codes
            )
        );

        // And: A caller holding and approving enough of both tokens for any entry.
        vm.assume(caller != address(0));
        amount = bound(amount, 1, Constants.MAX_FUZZED_AMOUNT);
        bool isToken0 = bound(vaultPick, 0, 1) == 0;
        address syncVault = contractAddress(
            address(almFactory),
            address(pool),
            isToken0 ? Constants.CONTRACT_SYNC_VAULT0 : Constants.CONTRACT_SYNC_VAULT1,
            codes.syncVault
        );
        address asyncVault = contractAddress(
            address(almFactory),
            address(pool),
            isToken0 ? Constants.CONTRACT_ASYNC_VAULT0 : Constants.CONTRACT_ASYNC_VAULT1,
            codes.asyncVault
        );
        token0.mint(caller, amount);
        token1.mint(caller, amount);
        vm.startPrank(caller);
        token0.approve(syncVault, amount);
        token1.approve(syncVault, amount);
        token0.approve(asyncVault, amount);
        token1.approve(asyncVault, amount);
        vm.stopPrank();
        entry = bound(entry, 0, 7);

        // When: The caller calls any entry point of a vault.
        address target = entry < 4 || entry == 6 ? syncVault : asyncVault;
        bytes memory data;
        if (entry == 0) data = abi.encodeWithSignature("deposit(uint256,address)", amount, caller);
        else if (entry == 1) data = abi.encodeWithSignature("mint(uint256,address)", amount, caller);
        else if (entry == 2) data = abi.encodeWithSignature("redeem(uint256,address,address)", amount, caller, caller);
        else if (entry == 3) data = abi.encodeWithSignature("withdraw(uint256,address,address)", amount, caller, caller);
        else if (entry == 4) data = abi.encodeCall(ALMVaultAsync.requestDeposit, (amount, caller, caller));
        else if (entry == 5) data = abi.encodeCall(ALMVaultAsync.requestRedeem, (amount, caller, caller));
        else data = abi.encodeWithSignature("setOperator(address,bool)", users.unprivilegedAddress, true);
        vm.prank(caller);
        (bool success, bytes memory result) = target.call(data);

        // Then: It reverts without data, the call into the core finding no code.
        assertFalse(success);
        assertEq(result.length, 0);
    }

    function testFuzz_Success_resumeCore_VaultsReportTheirConfiguration(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The steward creates the pool in its three transactions.
        setCoreCreated();

        // Then: Every vault's share is the core, and none is paused.
        address[4] memory list = vaultsOf(vaults);
        for (uint256 i; i < 4; ++i) {
            assertEq(BaseVault(list[i]).share(), address(core));
            assertFalse(BaseVault(list[i]).paused());
        }

        // And: The vaults over token0 have it as asset, the vaults over token1 token1.
        assertEq(BaseVault(vaults.syncVault0).asset(), address(token0));
        assertEq(BaseVault(vaults.asyncVault0).asset(), address(token0));
        assertEq(BaseVault(vaults.syncVault1).asset(), address(token1));
        assertEq(BaseVault(vaults.asyncVault1).asset(), address(token1));

        // And: The synchronous vaults take no requests.
        assertFalse(BaseVault(vaults.syncVault0).supportsInterface(type(IERC7540Deposit).interfaceId));
        assertFalse(BaseVault(vaults.syncVault1).supportsInterface(type(IERC7540Redeem).interfaceId));

        // And: The asynchronous vaults take requests in both queues.
        assertTrue(BaseVault(vaults.asyncVault0).supportsInterface(type(IERC7540Deposit).interfaceId));
        assertTrue(BaseVault(vaults.asyncVault0).supportsInterface(type(IERC7540Redeem).interfaceId));
        assertTrue(BaseVault(vaults.asyncVault1).supportsInterface(type(IERC7540Deposit).interfaceId));
        assertTrue(BaseVault(vaults.asyncVault1).supportsInterface(type(IERC7540Redeem).interfaceId));
    }

    function testFuzz_Success_resumeCore_VaultsAnswerToTheFactory(PoolState memory poolState, uint256 index) public {
        // Given: A factory with a core over the pool, and one of its four vaults.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        address[4] memory list = vaultsOf(vaults);
        BaseVault vault = BaseVault(list[bound(index, 0, list.length - 1)]);

        // When: The factory pauses the vault directly.
        vm.prank(address(almFactory));
        vault.setPaused(true);

        // Then: The vault is paused.
        assertTrue(vault.paused());
    }

    function testFuzz_Success_resumeCore_CoreResolvesItsSynchronousVaults(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The steward creates the pool in its three transactions.
        setCoreCreated();

        // Then: The core's ERC-7575 lookup returns the sync vault of each token.
        assertEq(core.vault(address(token0)), vaults.syncVault0);
        assertEq(core.vault(address(token1)), vaults.syncVault1);
    }

    function testFuzz_Success_resumeCore_HoldsNothing(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: The steward creates the pool in its three transactions.
        setCoreCreated();

        // Then: The factory holds neither pool token nor aLP.
        assertEq(token0.balanceOf(address(almFactory)), 0);
        assertEq(token1.balanceOf(address(almFactory)), 0);
        assertEq(core.balanceOf(address(almFactory)), 0);
    }
}
