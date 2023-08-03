// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {IPoolFactory} from "../factory/IPoolFactory.sol";

import {IERC20Router} from "./IERC20Router.sol";

contract ERC20Router is IERC20Router, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable POOL_FACTORY;

    constructor(address poolFactory) {
        POOL_FACTORY = poolFactory;
    }

    /// @inheritdoc IERC20Router
    function safeTransferFrom(address token, address from, address to, uint256 amount) external nonReentrant {
        if (!IPoolFactory(POOL_FACTORY).isPool(msg.sender)) revert ERC20Router__NotAuthorized();

        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
