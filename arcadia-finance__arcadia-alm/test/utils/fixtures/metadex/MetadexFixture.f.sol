/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IEmissionsHandler } from "./interfaces/IEmissionsHandler.sol";
import { IFactoryRegistry } from "./interfaces/IFactoryRegistry.sol";
import { ILeafMessageOrchestrator, IRootMessageOrchestrator } from "./interfaces/IMessageOrchestrators.sol";
import { ILeafVoter } from "./interfaces/ILeafVoter.sol";
import { IVoter } from "./interfaces/IVoter.sol";
import { Test } from "@forge-std/Test.sol";
import { WETH } from "@solady/tokens/WETH.sol";

/**
 * @notice Deploys the Metadex voter stack from the pinned bytecode, in leaf or root shape.
 */
abstract contract MetadexFixture is Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // A ChainState's Point packs into two slots, the ceiling follows it.
    uint256 internal constant CEILING_OFFSET = 2;

    // AccessControlEnumerable takes slots 0 and 1, three single-slot mappings precede chainStates.
    uint256 internal constant CHAIN_STATES_SLOT = 5;

    uint256 internal constant MAX_PIPS = 1_000_000;

    uint256 internal constant MIN_REDEEM_AMOUNT = MAX_PIPS;

    // Base is the Metadex root chain.
    uint256 internal constant ROOT_CHAIN_ID = 8453;

    // Minter.MAX_BASE_RATE, the ceiling emissions accrue against.
    uint232 internal constant MAX_BASE_RATE = 730_750_818_665_456_651_398_700_951_213;

    uint128 internal constant VOTING_POWER = 1e18;

    uint24 internal constant MAX_BAND_CEILING_PIPS = 1_000_000;

    uint24 internal constant MAX_BAND_FLOOR_PIPS = 500_000;

    uint24 internal constant MAX_BASE_RATE_CHANGE_PIPS = 50_000;

    // Must match the addresses foundry.toml links the metadex libraries against.
    address internal constant ALLOCATION_LOGIC_LIBRARY = 0x3000000000000000000000000000000000000001;

    address internal constant LEAF_ALLOCATION_LIBRARY = 0x3000000000000000000000000000000000000002;

    address internal constant REWARDS_LOGIC_LIBRARY = 0x3000000000000000000000000000000000000003;

    address internal constant VOTING_REWARDS_FACTORY_LIBRARY = 0x3000000000000000000000000000000000000004;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    address internal metadexGovernor = makeAddr("metadexGovernor");
    address internal metadexConfigAdmin = makeAddr("metadexConfigAdmin");
    address internal metadexGaugeManager = makeAddr("metadexGaugeManager");
    address internal metadexTokenRegistry = makeAddr("metadexTokenRegistry");

    ILeafVoter internal leafVoter;
    IFactoryRegistry internal factoryRegistry;
    address internal receiptToken;
    address internal rewardToken;
    address internal emissionsHandler;
    address internal messageOrchestrator;
    address internal votingRewardsFactory;
    WETH internal weth;

    // Root shape only.
    IVoter internal rootVoter;
    address internal rootToken;

    mapping(address gauge => bool weighted) internal gaugeWeighted;

    struct RootAddresses {
        address token;
        address minter;
        address voter;
        address rootOrchestrator;
        address leafOrchestrator;
        address leafVoter;
        uint48 migrationOpen;
    }

    /* //////////////////////////////////////////////////////////////
                                  ERRORS
    ////////////////////////////////////////////////////////////// */

    error CeilingSeedMismatch();
    error PredictedAddressMismatch();

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function deployMetadex(bool root) internal {
        weth = new WETH();
        vm.label(address(weth), "WETH");
        _deployLibraries();
        root ? _deployRoot() : _deployLeaf();

        votingRewardsFactory = deployCode(
            "out/VotingRewardsFactory.sol/VotingRewardsFactory.json", abi.encode(address(leafVoter), address(weth))
        );
        vm.label(votingRewardsFactory, "VotingRewardsFactory");

        if (factoryRegistry.leafVoter() != address(leafVoter)) revert PredictedAddressMismatch();
    }

    function _deployLibraries() private {
        deployCodeTo("out/AllocationLogicLibrary.sol/AllocationLogicLibrary.json", ALLOCATION_LOGIC_LIBRARY);
        vm.label(ALLOCATION_LOGIC_LIBRARY, "AllocationLogicLibrary");
        deployCodeTo("out/LeafAllocationLibrary.sol/LeafAllocationLibrary.json", LEAF_ALLOCATION_LIBRARY);
        vm.label(LEAF_ALLOCATION_LIBRARY, "LeafAllocationLibrary");
        deployCodeTo("out/RewardsLogicLibrary.sol/RewardsLogicLibrary.json", REWARDS_LOGIC_LIBRARY);
        vm.label(REWARDS_LOGIC_LIBRARY, "RewardsLogicLibrary");
        deployCodeTo(
            "out/VotingRewardsFactoryLibrary.sol/VotingRewardsFactoryLibrary.json", VOTING_REWARDS_FACTORY_LIBRARY
        );
        vm.label(VOTING_REWARDS_FACTORY_LIBRARY, "VotingRewardsFactoryLibrary");
    }

    function _deployLeaf() private {
        address predictedVoter = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        receiptToken =
            deployCode("out/ReceiptToken.sol/ReceiptToken.json", abi.encode(predictedVoter, "Receipt Token", "rTOKEN"));
        vm.label(receiptToken, "ReceiptToken");
        rewardToken = receiptToken;
        emissionsHandler = deployCode(
            "out/LeafEmissionsHandler.sol/LeafEmissionsHandler.json", abi.encode(predictedVoter, receiptToken)
        );
        vm.label(emissionsHandler, "EmissionsHandler");
        factoryRegistry = IFactoryRegistry(
            deployCode(
                "out/FactoryRegistry.sol/FactoryRegistry.json",
                abi.encode(address(0), predictedVoter, metadexTokenRegistry)
            )
        );
        vm.label(address(factoryRegistry), "FactoryRegistry");
        messageOrchestrator = deployCode(
            "out/LeafMessageOrchestrator.sol/LeafMessageOrchestrator.json",
            abi.encode(predictedVoter, ROOT_CHAIN_ID, address(0), uint256(0))
        );
        vm.label(messageOrchestrator, "LeafMessageOrchestrator");
        leafVoter = ILeafVoter(deployCode("out/LeafVoter.sol/LeafVoter.json", _leafVoterArgs()));
        vm.label(address(leafVoter), "LeafVoter");
        if (address(leafVoter) != predictedVoter) revert PredictedAddressMismatch();
    }

    function _deployRoot() private {
        uint256 stagedAt = vm.getBlockTimestamp() > 3 weeks ? vm.getBlockTimestamp() : 4 weeks;
        vm.warp(stagedAt - 3 weeks);

        RootAddresses memory predicted = _predictRootAddresses();

        rootToken = deployCode("out/Token.sol/Token.json", _tokenArgs(predicted));
        vm.label(rootToken, "Token");
        rewardToken = rootToken;
        if (rootToken != predicted.token) revert PredictedAddressMismatch();
        address minter = deployCode("out/Minter.sol/Minter.json", _minterArgs(predicted));
        vm.label(minter, "Minter");
        if (minter != predicted.minter) revert PredictedAddressMismatch();
        address voter = deployCode("out/Voter.sol/Voter.json", _voterArgs(predicted));
        vm.label(voter, "Voter");
        if (voter != predicted.voter) revert PredictedAddressMismatch();
        address rootOrchestrator =
            deployCode("out/RootMessageOrchestrator.sol/RootMessageOrchestrator.json", abi.encode(voter));
        vm.label(rootOrchestrator, "RootMessageOrchestrator");
        if (rootOrchestrator != predicted.rootOrchestrator) revert PredictedAddressMismatch();

        receiptToken = deployCode(
            "out/ReceiptToken.sol/ReceiptToken.json", abi.encode(predicted.leafVoter, "Receipt Token", "rTOKEN")
        );
        vm.label(receiptToken, "ReceiptToken");
        emissionsHandler =
            deployCode("out/RootEmissionsHandler.sol/RootEmissionsHandler.json", abi.encode(predicted.leafVoter));
        vm.label(emissionsHandler, "EmissionsHandler");
        factoryRegistry = IFactoryRegistry(
            deployCode(
                "out/FactoryRegistry.sol/FactoryRegistry.json",
                abi.encode(address(0), predicted.leafVoter, metadexTokenRegistry)
            )
        );
        vm.label(address(factoryRegistry), "FactoryRegistry");
        messageOrchestrator = deployCode(
            "out/LeafMessageOrchestrator.sol/LeafMessageOrchestrator.json",
            abi.encode(predicted.leafVoter, block.chainid, address(0), uint256(0))
        );
        vm.label(messageOrchestrator, "LeafMessageOrchestrator");
        if (messageOrchestrator != predicted.leafOrchestrator) revert PredictedAddressMismatch();
        leafVoter = ILeafVoter(deployCode("out/LeafVoter.sol/LeafVoter.json", _leafVoterArgs()));
        vm.label(address(leafVoter), "LeafVoter");
        if (address(leafVoter) != predicted.leafVoter) revert PredictedAddressMismatch();

        address adapter = deployCode(
            "out/RootLocalAdapter.sol/RootLocalAdapter.json", abi.encode(rootOrchestrator, messageOrchestrator)
        );
        vm.label(adapter, "RootLocalAdapter");
        vm.startPrank(metadexConfigAdmin);
        ILeafMessageOrchestrator(messageOrchestrator).setAdapter(adapter);
        IRootMessageOrchestrator(rootOrchestrator).setAdapter(block.chainid, adapter);
        vm.stopPrank();

        rootVoter = IVoter(voter);
        vm.prank(metadexConfigAdmin);
        rootVoter.registerChain(block.chainid);
        _seedChainCeiling(type(uint128).max);

        vm.warp(stagedAt);
    }

    function _leafVoterArgs() private view returns (bytes memory args) {
        args = abi.encode(
            metadexGovernor,
            metadexConfigAdmin,
            messageOrchestrator,
            receiptToken,
            address(factoryRegistry),
            metadexGaugeManager,
            uint48(0),
            uint48(1 weeks),
            uint256(100),
            metadexConfigAdmin,
            emissionsHandler,
            metadexGovernor
        );
        args = bytes.concat(
            args,
            abi.encode(
                address(0),
                address(0),
                metadexConfigAdmin,
                metadexConfigAdmin,
                address(0),
                address(0),
                address(0),
                address(0),
                uint256(1_000_000)
            )
        );
    }

    function _predictRootAddresses() private view returns (RootAddresses memory predicted) {
        uint64 nonce = vm.getNonce(address(this));
        predicted = RootAddresses({
            token: vm.computeCreateAddress(address(this), nonce),
            minter: vm.computeCreateAddress(address(this), nonce + 1),
            voter: vm.computeCreateAddress(address(this), nonce + 2),
            rootOrchestrator: vm.computeCreateAddress(address(this), nonce + 3),
            leafOrchestrator: vm.computeCreateAddress(address(this), nonce + 7),
            leafVoter: vm.computeCreateAddress(address(this), nonce + 8),
            // forge-lint: disable-next-line(unsafe-typecast)
            migrationOpen: uint48((vm.getBlockTimestamp() / 1 weeks + 1) * 1 weeks)
        });
    }

    function _tokenArgs(RootAddresses memory predicted) private view returns (bytes memory args) {
        args = abi.encode(
            predicted.minter,
            metadexGovernor,
            metadexGovernor,
            metadexGovernor,
            uint256(0),
            uint256(0),
            "Token",
            "TOKEN"
        );
    }

    function _minterArgs(RootAddresses memory predicted) private view returns (bytes memory args) {
        args = bytes.concat(
            abi.encode(
                predicted.token,
                predicted.voter,
                metadexGovernor,
                metadexGovernor,
                address(0),
                predicted.migrationOpen,
                MAX_BASE_RATE,
                MAX_BASE_RATE_CHANGE_PIPS
            ),
            abi.encode(
                uint48(1 weeks),
                uint24(0),
                MAX_BASE_RATE_CHANGE_PIPS,
                uint48(1 hours),
                uint48(4 weeks),
                MAX_BAND_FLOOR_PIPS,
                MAX_BAND_CEILING_PIPS
            )
        );
    }

    function _voterArgs(RootAddresses memory predicted) private view returns (bytes memory args) {
        args = bytes.concat(
            abi.encode(predicted.rootOrchestrator, metadexGovernor, predicted.minter, predicted.token),
            abi.encode(
                metadexGovernor,
                metadexConfigAdmin,
                metadexConfigAdmin,
                metadexConfigAdmin,
                metadexConfigAdmin,
                metadexConfigAdmin,
                metadexConfigAdmin,
                metadexGovernor,
                metadexGovernor,
                uint48(1 weeks),
                uint48(1 weeks)
            )
        );
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function addEmissionsToGauge(address gauge, uint256 emissions) internal {
        _allocateWeightToGauge(gauge);
        _setEmissionsPerVP(gauge, emissions);
        vm.warp(vm.getBlockTimestamp() + 1);
        _setEmissionsPerVP(gauge, 0);
    }

    function setChainStatus(ILeafVoter.ChainStatus status) internal {
        vm.prank(metadexConfigAdmin);
        leafVoter.setChainStatus(status);
    }

    function setMintable(bool mintable) internal {
        ILeafVoter.ChainStatus status = mintable ? ILeafVoter.ChainStatus.Active : ILeafVoter.ChainStatus.Paused;
        vm.mockCall(
            address(leafVoter), abi.encodeWithSelector(ILeafVoter.chainStatus.selector), abi.encode(uint8(status))
        );
    }

    function setMintableStatus(uint256 pick) internal {
        ILeafVoter.ChainStatus[2] memory statuses = [ILeafVoter.ChainStatus.Active, ILeafVoter.ChainStatus.Sunset];
        ILeafVoter.ChainStatus status = statuses[bound(pick, 0, 1)];
        if (leafVoter.chainStatus() != status) setChainStatus(status);
    }

    function setNotMintableStatus(uint256 pick) internal {
        ILeafVoter.ChainStatus[2] memory statuses = [ILeafVoter.ChainStatus.Paused, ILeafVoter.ChainStatus.Suspended];
        ILeafVoter.ChainStatus status = statuses[bound(pick, 0, 1)];
        if (leafVoter.chainStatus() != status) setChainStatus(status);
    }

    function setAnyStatus(uint256 pick) internal {
        ILeafVoter.ChainStatus status = ILeafVoter.ChainStatus(
            bound(pick, uint256(ILeafVoter.ChainStatus.Active), uint256(ILeafVoter.ChainStatus.Sunset))
        );
        if (leafVoter.chainStatus() != status) setChainStatus(status);
    }

    function setChainCeiling(uint256 ceiling) internal {
        _seedChainCeiling(ceiling);
    }

    function pendingRedeemsOf(address recipient) internal view returns (uint256 pendingAmount) {
        pendingAmount = IEmissionsHandler(emissionsHandler).pendingRedeems(recipient);
    }

    function _seedChainCeiling(uint256 ceiling) private {
        bytes32 target = bytes32(uint256(keccak256(abi.encode(block.chainid, CHAIN_STATES_SLOT))) + CEILING_OFFSET);
        vm.store(address(rootVoter), target, bytes32(ceiling));
        // forge-lint: disable-next-line(unused-return)
        (, uint256 stored,,,,,,,,) = rootVoter.chainStates(block.chainid);
        if (stored != ceiling) revert CeilingSeedMismatch();
    }

    function _allocateWeightToGauge(address gauge) private {
        if (gaugeWeighted[gauge]) return;
        gaugeWeighted[gauge] = true;

        ILeafVoter.TokenSnapshot memory snapshot =
            ILeafVoter.TokenSnapshot({ staked: VOTING_POWER, stakeEnd: 0, isPermanent: true });
        ILeafVoter.GaugeAllocation[] memory gauges = new ILeafVoter.GaugeAllocation[](1);
        gauges[0] = ILeafVoter.GaugeAllocation({ gauge: gauge, allocated: VOTING_POWER, data: "" });

        uint256 tokenId = uint256(uint160(gauge));
        vm.startPrank(messageOrchestrator);
        leafVoter.applyChainAllocation(tokenId, VOTING_POWER, 0, true, true, snapshot);
        leafVoter.applyGaugeAllocations(tokenId, type(uint48).max, 0, true, false, snapshot, gauges);
        vm.stopPrank();
    }

    function _setEmissionsPerVP(address gauge, uint256 emissionsPerVP) private {
        ILeafVoter.TokenSnapshot memory snapshot =
            ILeafVoter.TokenSnapshot({ staked: VOTING_POWER, stakeEnd: 0, isPermanent: true });
        vm.prank(messageOrchestrator);
        leafVoter.applyChainAllocation(uint256(uint160(gauge)), 0, emissionsPerVP, true, false, snapshot);
    }
}
