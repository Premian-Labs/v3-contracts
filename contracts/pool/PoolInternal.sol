// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Math} from "../libraries/Math.sol";
import {Position} from "../libraries/Position.sol";
import {PricingCurve} from "../libraries/PricingCurve.sol";
import {WadMath} from "../libraries/WadMath.sol";

import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is ERC1155EnumerableInternal {
    using LinkedList for LinkedList.List;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Data;
    using WadMath for uint256;

    error PoolInternal__ZeroSize();
    error PoolInternal__ExpiredOption();

    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    // ToDo : Define final number
    uint256 private constant PROTOCOL_FEE_RATE = 5e3; // 50%

    /**
     * @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
     * @param size The size of a trade (number of contracts)
     * @param premium The total cost of option(s) for a purchase
     * @return The taker fee for an option trade
     */
    function _takerFee(uint256 size, uint256 premium)
        internal
        pure
        returns (uint256)
    {
        uint256 premiumFee = (premium * 300) / INVERSE_BASIS_POINT; // 3% of premium
        uint256 notionalFee = (size * 30) / INVERSE_BASIS_POINT; // 0.3% of notional
        return Math.max(premiumFee, notionalFee);
    }

    function _getQuote(uint256 size, PoolStorage.Side tradeSide)
        internal
        view
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (size == 0) revert PoolInternal__ZeroSize();
        if (block.timestamp > l.maturity) revert PoolInternal__ExpiredOption();

        bool isBuy = tradeSide == PoolStorage.Side.BUY;

        uint256 totalPremium = 0;
        uint256 marketPrice = l.marketPrice;
        uint256 currentTick = l.tick;

        while (size > 0) {
            PricingCurve.Args memory args = PricingCurve.Args(
                l.liquidityRate,
                l.minTickDistance(),
                l.tickIndex.getPreviousNode(currentTick),
                l.tickIndex.getNextNode(currentTick),
                tradeSide
            );

            uint256 maxSize = PricingCurve.maxTradeSize(args, l.marketPrice);
            uint256 tradeSize = Math.min(size, maxSize);

            uint256 nextMarketPrice = PricingCurve.nextPrice(
                args,
                marketPrice,
                tradeSize
            );
            uint256 quotePrice = Math.mean(marketPrice, nextMarketPrice);
            uint256 premium = quotePrice.mulWad(tradeSize);
            uint256 takerFee = _takerFee(tradeSize, premium);
            uint256 takerPremium = premium + takerFee;

            // Update price and liquidity variables
            uint256 protocolFee = (takerFee * PROTOCOL_FEE_RATE) /
                INVERSE_BASIS_POINT;
            uint256 makerPremium = premium + (takerFee - protocolFee);

            // ToDo : Remove ?
            // l.globalFeeRate += (makerRebate * 1e18) / l.liquidityRate;
            totalPremium += isBuy ? takerPremium : makerPremium;

            marketPrice = nextMarketPrice;

            // Check if a tick cross is required
            if (maxSize > size) {
                // The trade can be done within the current tick range
                size = 0;
            } else {
                // The trade will require crossing into the next tick range
                size -= maxSize;
                currentTick = isBuy ? args.upper : args.lower;
            }
        }

        return totalPremium;
    }

    /**
     * @notice Calculates the current liquidity state for a position, given the initial state and current pool price.
     *             ▼    l                   u
     * ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     * BUY:  (0, D_s, (C_bid - (mean(P_U, P_T) * D_s)) / mean(P_T, P_L), 0)
     * SELL: (0, C_ask, D_l, 0)
     *
     *                  l                   u    ▼
     * ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     * BUY:  (C_bid, 0, 0, D_s)
     * SELL: (D_l * mean(P_L, P_T), 0, 0, C_ask)
     *
     *                  l         ▼         u
     * ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     * BUY (>= P_T):  (C_bid - D_s * mean(P_U, MP), (P_U - MP) / (P_U - P_T) * D_s, 0, D_s - (P_U - MP) / (P_U - P_T) * D_s)
     * BUY (< P_T):  (C_bid - D_s * mean(P_U, P_T) - mean(P_T, P_L) * (C_bid - D_s * mean(P_U, P_T)), D_s, 0, 0)
     * SELL (>= P_T): (D_l * mean(P_L, P_T), C_ask - (MP - P_T) / (P_U - P_T) * C_ask, 0, 0)
     * SELL (< P_T): (D_l * mean(P_L, MP), C_ask, D_l - (MP - P_L) / (P_T - P_L) * D_l, 0)
     */
    function _calculatePositionLiquidity(Position.Data memory position)
        internal
        view
        returns (
            uint256 collateral,
            uint256 long,
            uint256 short
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 marketPrice = l.marketPrice;
        uint256 transitionPrice = position.transitionPrice();

        if (position.rangeSide == PoolStorage.Side.BUY) {
            if (marketPrice <= position.lower) {
                collateral = position.contracts;
                long = (position.collateral -
                    Math.mean(position.upper, transitionPrice).mulWad(
                        position.contracts
                    )).divWad(Math.mean(transitionPrice, position.lower));
            } else if (marketPrice > position.upper) {
                collateral = position.collateral;
                short = position.contracts;
            } else {
                if (marketPrice >= position.upper) {
                    collateral +=
                        position.collateral -
                        position.contracts.mulWad(
                            Math.mean(position.upper, marketPrice)
                        );

                    collateral +=
                        ((position.upper - marketPrice) * position.contracts) /
                        (position.upper - transitionPrice);

                    short =
                        position.contracts -
                        ((position.upper - marketPrice) * position.contracts) /
                        (position.upper - transitionPrice);
                } else {
                    // ToDo : Make sure no value could be negative here
                    collateral +=
                        position.collateral -
                        position.contracts.mulWad(
                            Math.mean(position.upper, transitionPrice)
                        ) -
                        Math.mean(transitionPrice, position.lower).mulWad(
                            position.collateral -
                                position.contracts.mulWad(
                                    Math.mean(position.upper, transitionPrice)
                                )
                        );

                    collateral += position.contracts;
                }
            }
        } else {
            if (marketPrice <= position.lower) {
                collateral = position.collateral;
                long = position.contracts;
            } else if (marketPrice >= position.upper) {
                collateral = position.contracts.mulWad(
                    Math.mean(position.lower, transitionPrice)
                );
                short = position.collateral;
            } else {
                collateral += position.contracts.mulWad(
                    Math.mean(
                        position.lower,
                        Math.max(marketPrice, transitionPrice)
                    )
                );

                collateral +=
                    position.collateral -
                    ((marketPrice - Math.min(marketPrice, transitionPrice)) *
                        position.collateral) /
                    (position.upper - transitionPrice);

                long =
                    position.contracts -
                    ((Math.min(marketPrice, transitionPrice) - position.lower) *
                        position.contracts) /
                    (transitionPrice - position.lower);
            }
        }
    }

    /**
     * @notice Calculates the growth and exposure change between the lower and upper Ticks of a Position.
     *                  l         ▼         u
     * ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     * => (global - external(l) - external(u))
     *
     *             ▼    l                   u
     * ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     * => (global - (global - external(l)) - external(u))
     *
     *                  l                   u    ▼
     * ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     * => (global - external(l) - (global - external(u)))
     *
     * @param lower The lower-bound normalized price of the tick for a Position
     * @param upper The upper-bound normalized price of the tick for a Position
     * @return The fee growth within a Position since the last update
     */
    function _calculatePositionGrowth(uint256 lower, uint256 upper)
        internal
        view
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 globalFeeRate = l.globalFeeRate;

        // -------------------------------------------
        // Calculate the liqs ABOVE the tick => fa(i)
        // -------------------------------------------
        // NOTE: tick.price can be different than actual market_price
        uint256 lowerFeeRate = l.tick >= lower
            ? globalFeeRate - l.ticks[lower].externalFeeRate
            : l.ticks[lower].externalFeeRate;

        // -------------------------------------------
        // Calculate the liqs BELOW the tick => fb(i)
        // -------------------------------------------
        // NOTE: tick.price can be different than actual market_price
        uint256 upperFeeRate = l.tick >= upper
            ? globalFeeRate - l.ticks[upper].externalFeeRate
            : l.ticks[upper].externalFeeRate;

        return globalFeeRate - lowerFeeRate - upperFeeRate;
    }
}
