/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

struct Users {
    address payable owner;
    address payable admin;
    address payable guardian;
    address payable steward;
    address payable keeper;
    address payable liquidityProvider;
    address payable feeRecipient;
    address payable unprivilegedAddress;
}
