// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {IPoolFactory} from "../factory/IPoolFactory.sol";

import {IERC20Router} from "./IERC20Router.sol";

contract ERC20Router is IERC20Router {
    using SafeERC20 for IERC20;

    address public immutable POOL_FACTORY;

    constructor(address poolFactory) {
        POOL_FACTORY = poolFactory;
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) external {
        if (IPoolFactory(POOL_FACTORY).isPool(msg.sender) == false)
            revert ERC20Router__NotAuthorized();

        IERC20(token).safeTransferFrom(from, to, amount);
    }
}