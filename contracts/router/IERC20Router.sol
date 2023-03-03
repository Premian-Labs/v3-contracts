// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IERC20Router {
    error ERC20Router__NotAuthorized();

    function transferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) external;
}
