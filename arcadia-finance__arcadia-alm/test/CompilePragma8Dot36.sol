/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.36;

// forge-lint: disable-start(unused-import)
import { FactoryRegistry } from "@metadex/factories/FactoryRegistry.sol";
import { GaugeManager } from "@metadex/gauge-creation/GaugeManager.sol";
import { LeafEmissionsHandler } from "@metadex/handlers/LeafEmissionsHandler.sol";
import { LeafMessageOrchestrator } from "@metadex/bridge/LeafMessageOrchestrator.sol";
import { LeafVoter } from "@metadex/voter/LeafVoter.sol";
import { Minter } from "@metadex/minter/Minter.sol";
import { ReceiptToken } from "@metadex/token/ReceiptToken.sol";
import { RootEmissionsHandler } from "@metadex/handlers/RootEmissionsHandler.sol";
import { RootLocalAdapter } from "@metadex/bridge/RootLocalAdapter.sol";
import { RootMessageOrchestrator } from "@metadex/bridge/RootMessageOrchestrator.sol";
import { Token } from "@metadex/token/Token.sol";
import { Voter } from "@metadex/voter/Voter.sol";
import { VotingRewardsFactory } from "@metadex/rewards/VotingRewardsFactory.sol";
// forge-lint: disable-end(unused-import)

contract CompilePragma8Dot36 { }
