// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Math} from "../libraries/Math.sol";
import {Position} from "../libraries/Position.sol";
import {PricingCurve} from "../libraries/PricingCurve.sol";
import {Tick} from "../libraries/Tick.sol";
import {WadMath} from "../libraries/WadMath.sol";

import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IPoolInternal} from "./IPoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is IPoolInternal, ERC1155EnumerableInternal {
    using LinkedList for LinkedList.List;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Data;
    using WadMath for uint256;
    using Tick for Tick.Data;
    using SafeCast for uint256;
    using Math for uint256;
    using Math for int256;

    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    // ToDo : Define final number
    uint256 private constant PROTOCOL_FEE_RATE = 5e3; // 50%

    /**
     * @notice Adds liquidity to a pair of Ticks and if necessary, inserts
     *         the Tick(s) into the doubly-linked Tick list.
     *
     * @param p The Position to insert into Ticks.
     * @param left The normalized price of the left Tick for a new position.
     * @param right The normalized price of the right Tick for a new position.
     */
    function _insertTick(
        Position.Data memory p,
        uint256 left,
        uint256 right
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 lower = p.lower;
        uint256 upper = p.upper;

        if (
            left > lower ||
            l.tickIndex.getNextNode(left) < lower ||
            right < upper ||
            l.tickIndex.getPreviousNode(right) > upper ||
            left == right ||
            lower == upper
        ) revert Pool__TickInsertInvalid();

        int256 delta = p.phi(l.minTickDistance()).toInt256();

        if (p.rangeSide == PoolStorage.Side.SELL) {
            l.ticks[lower].delta += delta;
            l.ticks[upper].delta -= delta;
        } else {
            l.ticks[lower].delta -= delta;
            l.ticks[upper].delta += delta;
        }

        if (left != lower) {
            if (l.tickIndex.insertAfter(left, lower) == false)
                revert Pool__TickInsertFailed();

            if (p.rangeSide == PoolStorage.Side.SELL) {
                if (lower == l.marketPrice) {
                    l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
                    l.liquidityRate = l.liquidityRate.addInt256(delta);

                    if (l.tick < lower) l.tick = lower;
                }
            } else {
                l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
            }
        }

        if (right != upper) {
            if (l.tickIndex.insertBefore(right, upper) == false)
                revert Pool__TickInsertFailed();

            if (p.rangeSide == PoolStorage.Side.BUY) {
                l.ticks[upper] = l.ticks[upper].cross(l.globalFeeRate);
                if (l.tick <= upper) {
                    l.liquidityRate = l.liquidityRate.addInt256(delta);
                }
                if (l.tick < lower) {
                    l.tick = lower;
                }
            }
        }
    }

    /**
     * @notice Removes liquidity from a pair of Ticks and if necessary, removes
     *         the Tick(s) from the doubly-linked Tick list.
     * @param p The Position to insert into Ticks.
     * @param marketPrice The normalized market price
     */
    function _removeTick(Position.Data memory p, uint256 marketPrice) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 lower = p.lower;
        uint256 upper = p.upper;

        int256 phi = p.phi(l.minTickDistance()).toInt256();
        bool leftRangeSide = p.rangeSide == PoolStorage.Side.BUY;
        bool rightRangeSide = p.rangeSide == PoolStorage.Side.SELL;

        int256 lowerDelta = l.ticks[lower].delta;
        int256 upperDelta = l.ticks[upper].delta;

        // right-side original state:
        //   lower_tick.delta += phi
        //   upper_tick.delta -= phi

        if (rightRangeSide) {
            if (lower > marketPrice) {
                // |---------p----l------------> original state
                lowerDelta -= phi;
            } else {
                // |------------l---p---------> left-tick crossed
                lowerDelta += phi;
            }

            if (upper > marketPrice) {
                // |------------p----u--------> original state
                upperDelta += phi;
            } else {
                // |----------------u----p----> right-tick crossed
                upperDelta -= phi;
            }
        }

        // left-side original state:
        //   lower_tick.delta -= phi
        //   upper_tick.delta += phi

        if (leftRangeSide) {
            if (upper < marketPrice) {
                // <---------u----p-----------| original state
                upperDelta -= phi;
            } else {
                // # <--------------p----u------| right-tick crossed
                upperDelta += phi;
            }

            if (lower < marketPrice) {
                // <-----l----p---------------| original state
                lowerDelta += phi;
            } else {
                // <---------p---l------------| left-tick crossed
                lowerDelta -= phi;
            }
        }

        // ToDo : Test precision rounding errors and if we need to increase from 0 (Most likely yes)
        if (lowerDelta.abs() == 0) {
            l.tickIndex.remove(lower);
            delete l.ticks[lower];
        }

        // ToDo : Test precision rounding errors and if we need to increase from 0 (Most likely yes)
        if (upperDelta.abs() == 0) {
            l.tickIndex.remove(upper);
            delete l.ticks[upper];
        }
    }

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

        if (size == 0) revert Pool__ZeroSize();
        if (block.timestamp > l.maturity) revert Pool__ExpiredOption();

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
        returns (Position.Liquidity memory pLiq)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 marketPrice = l.marketPrice;
        uint256 transitionPrice = position.transitionPrice();

        if (position.rangeSide == PoolStorage.Side.BUY) {
            if (marketPrice <= position.lower) {
                pLiq.collateral = position.contracts;
                pLiq.long = (position.collateral -
                    Math.mean(position.upper, transitionPrice).mulWad(
                        position.contracts
                    )).divWad(Math.mean(transitionPrice, position.lower));
            } else if (marketPrice > position.upper) {
                pLiq.collateral = position.collateral;
                pLiq.short = position.contracts;
            } else {
                if (marketPrice >= position.upper) {
                    pLiq.collateral +=
                        position.collateral -
                        position.contracts.mulWad(
                            Math.mean(position.upper, marketPrice)
                        );

                    pLiq.collateral +=
                        ((position.upper - marketPrice) * position.contracts) /
                        (position.upper - transitionPrice);

                    pLiq.short =
                        position.contracts -
                        ((position.upper - marketPrice) * position.contracts) /
                        (position.upper - transitionPrice);
                } else {
                    // ToDo : Make sure no value could be negative here
                    pLiq.collateral +=
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

                    pLiq.collateral += position.contracts;
                }
            }
        } else {
            if (marketPrice <= position.lower) {
                pLiq.collateral = position.collateral;
                pLiq.long = position.contracts;
            } else if (marketPrice >= position.upper) {
                pLiq.collateral = position.contracts.mulWad(
                    Math.mean(position.lower, transitionPrice)
                );
                pLiq.short = position.collateral;
            } else {
                pLiq.collateral += position.contracts.mulWad(
                    Math.mean(
                        position.lower,
                        Math.max(marketPrice, transitionPrice)
                    )
                );

                pLiq.collateral +=
                    position.collateral -
                    ((marketPrice - Math.min(marketPrice, transitionPrice)) *
                        position.collateral) /
                    (position.upper - transitionPrice);

                pLiq.long =
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

    /**
     * @notice Creates a Tick for a given price, or returns the existing tick.
     * @param price The price of the Tick
     * @return tick The Tick for a given price
     */
    function _getOrCreateTick(uint256 price)
        internal
        returns (Tick.Data memory tick)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.nodeExists(price)) return l.ticks[price];

        tick = Tick.Data(
            price,
            0,
            price <= l.marketPrice ? l.globalFeeRate : 0
        );

        l.ticks[price] = tick;
    }

    function _updatePosition(Position.Data memory p)
        internal
        returns (Position.Liquidity memory pLiq)
    {
        Tick.Data memory lowerTick = _getOrCreateTick(p.lower);
        Tick.Data memory upperTick = _getOrCreateTick(p.upper);
        // ToDo : Implement
    }

    function _claim() internal {
        // ToDo : Implement
    }

    function _verifyTickWidth(uint256 price, uint256 minTickDistance)
        internal
        pure
    {
        if (price % minTickDistance != 0) revert Pool__TickWidthInvalid();
    }

    /**
     * @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
     * @param owner The Agent that owns the exposure change of the Position
     * @param operator The Agent that can control modifications to the Position
     * @param p The LP position to insert
     * @param left The normalized price of the tick at the left of the position
     * @param right The normalized price of the tick at th right of the position
     */
    function _deposit(
        address owner,
        address operator,
        Position.Data memory p,
        uint256 left,
        uint256 right
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 minTickDistance = l.minTickDistance();
        _verifyTickWidth(p.lower, minTickDistance);
        _verifyTickWidth(p.upper, minTickDistance);

        bool isBuy = p.rangeSide == PoolStorage.Side.BUY;

        if (p.upper > l.marketPrice && isBuy)
            revert Pool__BuyPositionBelowMarketPrice();
        if (p.lower > l.marketPrice && !isBuy)
            revert Pool__SellPositionAboveMarketPrice();

        // ToDo : Transfer token (Collateral or contract) -> Need first to figure out token ids structure / decimals normalization
        //    agent.transfer_from(
        //    position.collateral,
        //    position.contracts if position.side == RangeSide.SELL else Decimal('0'),
        //    position.contracts if position.side == RangeSide.BUY else Decimal('0'),
        //    self,
        //    )

        _updatePosition(p);

        if ((isBuy && p.lower >= l.tick) || (!isBuy && p.upper > l.tick)) {
            l.liquidityRate += p.phi(minTickDistance);
        }

        _insertTick(p, left, right);
    }

    function _withdraw() internal {
        // ToDo : Implement
    }

    function _trade() internal {
        // ToDo : Implement
    }

    function _annihilate() internal {
        // ToDo : Implement
    }

    function _transferPosition() internal {
        // ToDo : Implement
    }

    function _transferTrade() internal {
        // ToDo : Implement
    }

    function _exercise() internal {
        // ToDo : Implement
    }

    function _settle() internal {
        // ToDo : Implement
    }

    function _settlePosition() internal {
        // ToDo : Implement
    }

    /////////////////////////////////////////////
    // ToDo : Move somewhere else auto functions ?

    function _exerciseAuto() internal {
        // ToDo : Implement
    }

    function _settleAuto() internal {
        // ToDo : Implement
    }

    function _settlePositionAuto() internal {
        // ToDo : Implement
    }
}
