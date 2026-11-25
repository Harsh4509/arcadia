/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20Mock } from "./ERC20Mock.sol";

// forge-lint: disable-next-item(erc20-unchecked-transfer)
contract LockProbeRouterMock {
    address public target;
    bytes public probe;
    bool public success;
    bytes public result;

    function arm(address target_, bytes memory probe_) external {
        target = target_;
        probe = probe_;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, address recipient) external {
        (success, result) = target.staticcall(probe);

        ERC20Mock(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        ERC20Mock(tokenOut).mint(recipient, amountOut);
    }
}
