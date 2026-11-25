/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20 } from "@solady/tokens/ERC20.sol";

/**
 * @notice ERC20 with public minting for tests.
 */
contract ERC20Mock is ERC20 {
    uint8 internal immutable DECIMALS;

    string internal name_;
    string internal symbol_;

    constructor(string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals) {
        name_ = tokenName;
        symbol_ = tokenSymbol;
        DECIMALS = tokenDecimals;
    }

    function name() public view override returns (string memory) {
        return name_;
    }

    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
