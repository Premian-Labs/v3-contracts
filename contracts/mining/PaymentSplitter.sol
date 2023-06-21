// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {IVxPremia} from "../staking/IVxPremia.sol";

import {IPaymentSplitter} from "./IPaymentSplitter.sol";

contract PaymentSplitter is IPaymentSplitter {
    using SafeERC20 for IERC20;

    address public immutable TOKEN;
    address public immutable VXPREMIA;

    constructor(address token, address vxPremia) {
        TOKEN = token;
        VXPREMIA = vxPremia;
    }

    /// @notice Distributes rewards to vxPREMIA staking contract - caller must approve `amount` before calling
    /// @param amount Amount of reward tokens to distribute
    function addReward(uint256 amount) external {
        IERC20(TOKEN).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(TOKEN).approve(VXPREMIA, amount);
        IVxPremia(VXPREMIA).addRewards(amount);
    }
}
