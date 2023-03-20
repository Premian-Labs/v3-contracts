// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC4626Internal} from "@solidstate/contracts/interfaces/IERC4626Internal.sol";
import {IERC20Internal} from "@solidstate/contracts/interfaces/IERC20Internal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";

interface IVault is IERC4626Internal, IERC20Internal {
    event UpdateQuotes();

    event Trade(
        address indexed user,
        address indexed pool,
        UD60x18 size,
        bool isBuy,
        UD60x18 premium,
        UD60x18 takerFee,
        UD60x18 makerRebate,
        UD60x18 vaultFee
    );

    event Swap(
        address indexed sender,
        address recipient,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        UD60x18 amountIn,
        UD60x18 amountOut,
        UD60x18 takerFee,
        UD60x18 makerRebate,
        UD60x18 vaultFee
    );

    event ManagementFeePaid(address indexed receiver, uint256 managementFee);

    event PerformanceFeePaid(address indexed receiver, uint256 performanceFee);

    function getTradeQuote(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external view returns (uint256 maxSize, uint256 price);

    function trade(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external;
}
