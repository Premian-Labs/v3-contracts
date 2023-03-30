// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IERC4626Internal} from "@solidstate/contracts/interfaces/IERC4626Internal.sol";
import {IERC20Internal} from "@solidstate/contracts/interfaces/IERC20Internal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";

interface IVault is IERC4626Internal, IERC20Internal {
    event UpdateQuotes();

    event Trade(
        address indexed user,
        address indexed pool,
        UD60x18 contractSize,
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

    event Borrow(
        bytes32 indexed borrowId,
        address indexed from,
        IERC20 indexed borrowToken,
        IERC20 collateralToken,
        UD60x18 sizeBorrowed,
        UD60x18 collateralLocked,
        UD60x18 borrowFee
    );

    event BorrowLiquidated(
        bytes32 indexed borrowId,
        address indexed from,
        IERC20 indexed collateralToken,
        UD60x18 collateralLiquidated
    );

    event RepayBorrow(
        bytes32 indexed borrowId,
        address indexed from,
        IERC20 indexed borrowToken,
        IERC20 collateralToken,
        UD60x18 amountRepaid,
        UD60x18 collateralUnlocked,
        UD60x18 repayFee
    );

    event ManagementFeePaid(address indexed recipient, uint256 managementFee);

    event PerformanceFeePaid(address indexed recipient, uint256 performanceFee);

    function getTradeQuote(
        UD60x18 strike,
        uint64 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 maxSize, uint256 price);

    function trade(
        UD60x18 strike,
        uint64 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) external;
}
