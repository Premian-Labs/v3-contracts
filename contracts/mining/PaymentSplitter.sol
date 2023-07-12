// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {IVxPremia} from "../staking/IVxPremia.sol";

import {IPaymentSplitter} from "./IPaymentSplitter.sol";
import {IMiningAddRewards} from "./IMiningAddRewards.sol";

contract PaymentSplitter is IPaymentSplitter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable PREMIA;
    IERC20 public immutable USDC;
    IVxPremia public immutable VX_PREMIA;
    IMiningAddRewards public immutable MINING;

    constructor(IERC20 premia, IERC20 usdc, IVxPremia vxPremia, IMiningAddRewards mining) {
        PREMIA = premia;
        USDC = usdc;
        VX_PREMIA = vxPremia;
        MINING = mining;
    }

    /// @notice Distributes rewards to vxPREMIA staking contract, and send back PREMIA leftover to mining contract
    /// @param premiaAmount Amount of PREMIA to send back to mining contract
    /// @param usdcAmount Amount of USDC to send to vxPREMIA staking contract
    function pay(uint256 premiaAmount, uint256 usdcAmount) external nonReentrant {
        if (premiaAmount > 0) {
            PREMIA.safeTransferFrom(msg.sender, address(this), premiaAmount);
            PREMIA.approve(address(MINING), premiaAmount);
            MINING.addRewards(premiaAmount);
        }

        if (usdcAmount > 0) {
            USDC.safeTransferFrom(msg.sender, address(this), usdcAmount);
            USDC.approve(address(VX_PREMIA), usdcAmount);
            VX_PREMIA.addRewards(usdcAmount);
        }
    }
}
