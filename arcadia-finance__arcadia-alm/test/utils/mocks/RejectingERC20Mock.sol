/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20Mock } from "./ERC20Mock.sol";

/**
 * @notice ERC20 with public minting whose transfers to one recipient revert, for tests.
 */
contract RejectingERC20Mock is ERC20Mock {
    address public rejected;

    error TransferRejected();

    constructor(uint8 tokenDecimals) ERC20Mock("", "", tokenDecimals) { }

    function reject(address recipient) external {
        rejected = recipient;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == rejected) revert TransferRejected();
        return super.transfer(to, amount);
    }
}
