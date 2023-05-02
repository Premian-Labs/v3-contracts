// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

import {Position} from "../libraries/Position.sol";

interface IPoolDepositWithdraw is IPoolInternal {
    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    ///         If the pool uses WETH as collateral, it is possible to send ETH to this function and it will be wrapped into WETH.
    ///         Any excess ETH sent will be refunded to the `msg.sender` as WETH.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas (18 decimals)
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas (18 decimals)
    /// @param size The position size to deposit (18 decimals)
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) (18 decimals)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) (18 decimals)
    /// @return delta The amount of collateral / longs / shorts deposited
    function deposit(
        Position.Key calldata p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external returns (Position.Delta memory delta);

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    ///         If the pool uses WETH as collateral, it is possible to send ETH to this function and it will be wrapped into WETH.
    ///         Any excess ETH sent will be refunded to the `msg.sender` as WETH.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas (18 decimals)
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas (18 decimals)
    /// @param size The position size to deposit (18 decimals)
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) (18 decimals)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) (18 decimals)
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)
    /// @return delta The amount of collateral / longs / shorts deposited
    function deposit(
        Position.Key calldata p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        bool isBidIfStrandedMarketPrice
    ) external returns (Position.Delta memory delta);

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param p The position key
    /// @param size The position size to withdraw (18 decimals)
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) (18 decimals)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) (18 decimals)
    /// @return delta The amount of collateral / longs / shorts withdrawn
    function withdraw(
        Position.Key calldata p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external returns (Position.Delta memory delta);

    /// @notice Get nearest ticks below `lower` and `upper`.
    ///         NOTE : If no tick between `lower` and `upper`, then the nearest tick below `upper`, will be `lower`
    /// @param lower The lower bound of the range (18 decimals)
    /// @param upper The upper bound of the range (18 decimals)
    /// @return nearestBelowLower The nearest tick below `lower` (18 decimals)
    /// @return nearestBelowUpper The nearest tick below `upper` (18 decimals)
    function getNearestTicksBelow(
        UD60x18 lower,
        UD60x18 upper
    )
        external
        view
        returns (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper);
}
