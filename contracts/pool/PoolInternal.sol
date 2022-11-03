// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {Tick} from "../libraries/Tick.sol";
import {WadMath} from "../libraries/WadMath.sol";

import {IPoolInternal} from "./IPoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is IPoolInternal, ERC1155EnumerableInternal {
    using LinkedList for LinkedList.List;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using Pricing for Pricing.Args;
    using WadMath for uint256;
    using Tick for Tick.Data;
    using SafeCast for uint256;
    using Math for int256;
    using UintUtils for uint256;

    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    // ToDo : Define final number
    uint256 private constant PROTOCOL_FEE_RATE = 5e3; // 50%

    /**
     * @notice Adds liquidity to a pair of Ticks and if necessary, inserts
     *         the Tick(s) into the doubly-linked Tick list.
     *
     * @param p The position key
     * @param left The normalized price of the left Tick for a new position.
     * @param right The normalized price of the right Tick for a new position.
     */
    function _insertTick(
        Position.Key memory p,
        Position.Data memory pData,
        uint256 left,
        uint256 right
    ) internal {
        // ToDo : Update
        //        PoolStorage.Layout storage l = PoolStorage.layout();
        //
        //        uint256 lower = p.lower;
        //        uint256 upper = p.upper;
        //
        //        if (
        //            left > lower ||
        //            l.tickIndex.getNextNode(left) < lower ||
        //            right < upper ||
        //            l.tickIndex.getPreviousNode(right) > upper ||
        //            left == right ||
        //            lower == upper
        //        ) revert Pool__TickInsertInvalid();
        //
        //        int256 delta = p.phi(pData, l.minTickDistance()).toInt256();
        //
        //        if (p.rangeSide == Position.Side.SELL) {
        //            l.ticks[lower].delta += delta;
        //            l.ticks[upper].delta -= delta;
        //        } else {
        //            l.ticks[lower].delta -= delta;
        //            l.ticks[upper].delta += delta;
        //        }
        //
        //        if (left != lower) {
        //            if (l.tickIndex.insertAfter(left, lower) == false)
        //                revert Pool__TickInsertFailed();
        //
        //            if (p.rangeSide == Position.Side.SELL) {
        //                if (lower == l.marketPrice) {
        //                    l.liquidityRate = l.liquidityRate.add(
        //                        l.ticks[lower].delta
        //                    );
        //                    l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
        //
        //                    if (l.tick < lower) l.tick = lower;
        //                }
        //            } else {
        //                l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
        //            }
        //        }
        //
        //        if (right != upper) {
        //            if (l.tickIndex.insertBefore(right, upper) == false)
        //                revert Pool__TickInsertFailed();
        //
        //            if (p.rangeSide == Position.Side.BUY) {
        //                if (l.tick <= upper) {
        //                    l.liquidityRate = l.liquidityRate.add(
        //                        l.ticks[upper].delta
        //                    );
        //                }
        //                l.ticks[upper] = l.ticks[upper].cross(l.globalFeeRate);
        //
        //                if (l.tick < lower) {
        //                    l.tick = lower;
        //                }
        //            }
        //        }
    }

    /**
     * @notice Removes liquidity from a pair of Ticks and if necessary, removes
     *         the Tick(s) from the doubly-linked Tick list.
     * @param p The position key
     * @param marketPrice The normalized market price
     */
    function _removeTick(
        Position.Key memory p,
        Position.Data memory pData,
        uint256 marketPrice
    ) internal {
        // ToDo : Update
        //        PoolStorage.Layout storage l = PoolStorage.layout();
        //
        //        uint256 lower = p.lower;
        //        uint256 upper = p.upper;
        //
        //        int256 phi = p.phi(pData, l.minTickDistance()).toInt256();
        //        bool leftRangeSide = p.rangeSide == Position.Side.BUY;
        //        bool rightRangeSide = p.rangeSide == Position.Side.SELL;
        //
        //        int256 lowerDelta = l.ticks[lower].delta;
        //        int256 upperDelta = l.ticks[upper].delta;
        //
        //        // right-side original state:
        //        //   lower_tick.delta += phi
        //        //   upper_tick.delta -= phi
        //
        //        if (rightRangeSide) {
        //            if (lower > marketPrice) {
        //                // |---------p----l------------> original state
        //                lowerDelta -= phi;
        //            } else {
        //                // |------------l---p---------> left-tick crossed
        //                lowerDelta += phi;
        //            }
        //
        //            if (upper > marketPrice) {
        //                // |------------p----u--------> original state
        //                upperDelta += phi;
        //            } else {
        //                // |----------------u----p----> right-tick crossed
        //                upperDelta -= phi;
        //            }
        //        }
        //
        //        // left-side original state:
        //        //   lower_tick.delta -= phi
        //        //   upper_tick.delta += phi
        //
        //        if (leftRangeSide) {
        //            if (upper < marketPrice) {
        //                // <---------u----p-----------| original state
        //                upperDelta -= phi;
        //            } else {
        //                // # <--------------p----u------| right-tick crossed
        //                upperDelta += phi;
        //            }
        //
        //            if (lower < marketPrice) {
        //                // <-----l----p---------------| original state
        //                lowerDelta += phi;
        //            } else {
        //                // <---------p---l------------| left-tick crossed
        //                lowerDelta -= phi;
        //            }
        //        }
        //
        //        // ToDo : Test precision rounding errors and if we need to increase from 0 (Most likely yes)
        //        if (lowerDelta.abs() == 0) {
        //            l.tickIndex.remove(lower);
        //            delete l.ticks[lower];
        //        }
        //
        //        // ToDo : Test precision rounding errors and if we need to increase from 0 (Most likely yes)
        //        if (upperDelta.abs() == 0) {
        //            l.tickIndex.remove(upper);
        //            delete l.ticks[upper];
        //        }
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
        uint256 premiumFee = (premium * 300) / INVERSE_BASIS_POINT;
        // 3% of premium
        uint256 notionalFee = (size * 30) / INVERSE_BASIS_POINT;
        // 0.3% of notional
        return Math.max(premiumFee, notionalFee);
    }

    function _getQuote(uint256 size, Position.Side tradeSide)
        internal
        view
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // ToDo : Add internal function for those checks ?
        if (size == 0) revert Pool__ZeroSize();
        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

        bool isBuy = tradeSide == Position.Side.BUY;

        Pricing.Args memory pricing = Pricing.Args(
            l.liquidityRate,
            l.marketPrice,
            l.currentTick,
            l.tickIndex.getNextNode(l.currentTick),
            tradeSide
        );

        uint256 liquidity = pricing.liquidity();
        uint256 maxSize = pricing.maxTradeSize();

        uint256 totalPremium = 0;

        while (size > 0) {
            uint256 tradeSize = Math.min(size, maxSize);

            uint256 nextPrice;
            // Compute next price
            if (liquidity == 0) {
                nextPrice = isBuy ? pricing.upper : pricing.lower;
            } else {
                uint256 priceDelta = (pricing.upper - pricing.lower).mulWad(
                    tradeSize.divWad(liquidity)
                );

                nextPrice = isBuy
                    ? pricing.marketPrice + priceDelta
                    : pricing.marketPrice - priceDelta;
            }

            {
                uint256 premium = Math
                    .average(pricing.marketPrice, nextPrice)
                    .mulWad(tradeSize);
                // quotePrice * tradeSize
                uint256 takerPremium = premium + _takerFee(size, premium);

                totalPremium += isBuy ? takerPremium : premium;
                pricing.marketPrice = nextPrice;
            }

            if (maxSize >= size) {
                size = 0;
            } else {
                // Cross tick
                size -= maxSize;

                // ToDo : Make sure this cant underflow
                // Adjust liquidity rate
                pricing.liquidityRate = pricing.liquidityRate.add(
                    l.ticks[isBuy ? pricing.upper : pricing.lower].delta
                );

                // Set new lower and upper bounds
                pricing.lower = isBuy
                    ? pricing.upper
                    : l.tickIndex.getPreviousNode(pricing.lower);
                pricing.upper = l.tickIndex.getNextNode(pricing.lower);

                // Compute new liquidity
                liquidity = pricing.liquidity();
                maxSize = pricing.maxTradeSize();
            }
        }

        return totalPremium;
    }

    // ToDo : Remove
    //    function _getClaimableFees(Position.Key memory p)
    //        internal
    //        view
    //        returns (uint256)
    //    {
    //        PoolStorage.Layout storage l = PoolStorage.layout();
    //        Position.Data storage pData = l.positions[p.keyHash()];
    //
    //        uint256 feeGrowthRate = _calculatePositionGrowth(p.lower, p.upper);
    //
    //        return
    //            (feeGrowthRate - pData.lastFeeRate).mulWad(
    //                p.phi(pData, l.minTickDistance())
    //            );
    //    }

    // ToDo : Remove
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
    function _calculatePositionLiquidity(
        Position.Key memory p,
        Position.Data memory pData
    ) internal view returns (Position.Liquidity memory pLiq) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 marketPrice = l.marketPrice;
        uint256 transitionPrice = p.transitionPrice(pData);

        if (pData.side == Position.Side.BUY) {
            if (marketPrice <= p.lower) {
                pLiq.collateral = pData.contracts;
                pLiq.long = (pData.collateral -
                    Math.average(p.upper, transitionPrice).mulWad(
                        pData.contracts
                    )).divWad(Math.average(transitionPrice, p.lower));
            } else if (marketPrice > p.upper) {
                pLiq.collateral = pData.collateral;
                pLiq.short = pData.contracts;
            } else {
                if (marketPrice >= p.upper) {
                    pLiq.collateral +=
                        pData.collateral -
                        pData.contracts.mulWad(
                            Math.average(p.upper, marketPrice)
                        );

                    pLiq.collateral +=
                        ((p.upper - marketPrice) * pData.contracts) /
                        (p.upper - transitionPrice);

                    pLiq.short =
                        pData.contracts -
                        ((p.upper - marketPrice) * pData.contracts) /
                        (p.upper - transitionPrice);
                } else {
                    // ToDo : Make sure no value could be negative here
                    pLiq.collateral +=
                        pData.collateral -
                        pData.contracts.mulWad(
                            Math.average(p.upper, transitionPrice)
                        ) -
                        Math.average(transitionPrice, p.lower).mulWad(
                            pData.collateral -
                                pData.contracts.mulWad(
                                    Math.average(p.upper, transitionPrice)
                                )
                        );

                    pLiq.collateral += pData.contracts;
                }
            }
        } else {
            if (marketPrice <= p.lower) {
                pLiq.collateral = pData.collateral;
                pLiq.long = pData.contracts;
            } else if (marketPrice >= p.upper) {
                pLiq.collateral = pData.contracts.mulWad(
                    Math.average(p.lower, transitionPrice)
                );
                pLiq.short = pData.collateral;
            } else {
                pLiq.collateral += pData.contracts.mulWad(
                    Math.average(
                        p.lower,
                        Math.max(marketPrice, transitionPrice)
                    )
                );

                pLiq.collateral +=
                    pData.collateral -
                    ((marketPrice - Math.min(marketPrice, transitionPrice)) *
                        pData.collateral) /
                    (p.upper - transitionPrice);

                pLiq.long =
                    pData.contracts -
                    ((Math.min(marketPrice, transitionPrice) - p.lower) *
                        pData.contracts) /
                    (transitionPrice - p.lower);
            }
        }
    }

    // ToDo : Remove
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
        uint256 lowerFeeRate = l.currentTick >= lower
            ? globalFeeRate - l.ticks[lower].externalFeeRate
            : l.ticks[lower].externalFeeRate;

        // -------------------------------------------
        // Calculate the liqs BELOW the tick => fb(i)
        // -------------------------------------------
        // NOTE: tick.price can be different than actual market_price
        uint256 upperFeeRate = l.currentTick >= upper
            ? globalFeeRate - l.ticks[upper].externalFeeRate
            : l.ticks[upper].externalFeeRate;

        return globalFeeRate - lowerFeeRate - upperFeeRate;
    }

    /**
     * @notice Updates the amount of fees an LP can claim for a position (without claiming).
     */
    function _updateClaimableFees(
        Position.Data storage pData,
        uint256 feeRate,
        uint256 liquidityPerTick
    ) internal {
        // Compute the claimable fees
        uint256 claimableFees = (feeRate - pData.lastFeeRate).mulWad(
            liquidityPerTick
        );
        pData.claimableFees += claimableFees;

        // Reset the initial range rate of the position
        pData.lastFeeRate = feeRate;
    }

    /**
     * @notice Update the collateral and contracts upon deposit / withdrawal.
     *
     * Withdrawals.
     * While straddling the market price only full withdrawals are
     * admissible. If the market price is outside of the tick range.
     */
    function _updatePosition(
        Position.Key memory p,
        Position.Data storage pData,
        uint256 collateral,
        uint256 contracts,
        uint256 price,
        bool withdraw
    ) internal {
        // Straddled price
        if (withdraw && p.lower < price && price < p.upper) {
            uint256 _collateral = p.bid(pData, price) + p.ask(pData, price);
            uint256 _contracts = p.short(pData, price) + p.long(pData, price);

            if (collateral != _collateral || contracts != _contracts)
                revert Pool__FullWithdrawalExpected();

            // Complete full withdrawal
            pData.collateral = 0;
            pData.contracts = 0;
            return;
        }

        // Compute if the position is modifiable, then modify position
        // A position is modifiable if its side does not need updating
        bool isOrderLeft = p.upper <= price;

        bool isBuy = pData.side == Position.Side.BUY;
        if (!isBuy == isOrderLeft) {
            if (!isBuy) {
                uint256 _collateral = withdraw
                    ? pData.collateral - collateral
                    : pData.collateral + collateral;
                uint256 _contracts = withdraw
                    ? pData.contracts - contracts
                    : pData.contracts + contracts;

                if (_collateral < p.averagePrice().mulWad(_contracts))
                    revert Pool__InsufficientCollateral();
            }

            if (withdraw) {
                if (
                    collateral > pData.collateral || contracts > pData.contracts
                ) revert Pool__InsufficientFunds();

                pData.collateral -= collateral;
                pData.contracts -= contracts;
            } else {
                pData.collateral += collateral;
                pData.contracts += contracts;
            }

            Position.Side newSide = isBuy
                ? Position.Side.SELL
                : Position.Side.BUY;

            return;
        }

        // Convert position to opposite side to make it modifiable
        uint256 _collateral;
        uint256 _contracts;
        if (!isBuy) {
            _collateral = pData.contracts;
            _contracts = p.liquidity(pData).mulWad(p.averagePrice());
        } else {
            _collateral = p.liquidity(pData).mulWad(p.averagePrice());
            _contracts = pData.collateral;
        }

        pData.collateral = _collateral;
        pData.contracts = _contracts;
        pData.side = isBuy ? Position.Side.SELL : Position.Side.BUY;

        _updatePosition(p, pData, collateral, contracts, price, withdraw);
    }

    function _claim() internal {
        // ToDo : Implement
    }

    function _verifyTickWidth(uint256 price) internal pure {
        if (price % Pricing.MIN_TICK_DISTANCE != 0)
            revert Pool__TickWidthInvalid();
    }

    /**
     * @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
     * @param p The position key
     * @param collateral The amount of collateral to be deposited
     * @param contracts The amount of contracts to be deposited
     * @param left The normalized price of the tick at the left of the position
     * @param right The normalized price of the tick at th right of the position
     */
    function _deposit(
        Position.Key memory p,
        Position.Side side,
        uint256 collateral,
        uint256 contracts,
        uint256 left,
        uint256 right
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        // Check if market price is stranded
        //        bool isMarketPriceStranded

        bool isBuy = side == Position.Side.BUY;

        // Fix for if stranded market price
        if (
            l.liquidityRate == 0 &&
            p.lower >= l.currentTick &&
            p.upper <= l.tickIndex.getNextNode(l.currentTick)
        ) {
            l.marketPrice = isBuy ? p.upper : p.lower;
        }

        if (isBuy) {
            // Check if valid buy order
            if (p.upper > l.marketPrice) revert Pool__InvalidBuyOrder();
        } else {
            // Check if valid sell order
            if (p.lower < l.marketPrice) revert Pool__InvalidSellOrder();
        }

        // Transfer funds from the LP to the pool
        /*
        info.owner.transfer_from(
            order.collateral,
            order.contracts if side == TradeSide.SELL else Decimal("0"),
            order.contracts if side == TradeSide.BUY else Decimal("0"),
            self
        )
        */

        // If ticks dont exist they are created and inserted into the linked list
        // ToDo : Do we need the vars ?
        //        Tick.Data memory lowerTick = _getOrCreateTick(p.lower);
        //        Tick.Data memory upperTick = _getOrCreateTick(p.upper);
        _getOrCreateTick(p.lower);
        _getOrCreateTick(p.upper);

        // Check if there is an existing position
        Position.Data storage pData = l.positions[p.keyHash()];
        // ToDo : Implement
        uint256 feeRate;
        //        fee_rate = self.tick_system.range_fee_rate(
        //            lower_tick,
        //            upper_tick
        //        );

        uint256 liquidityPerTick;

        if (pData.collateral + pData.contracts > 0) {
            liquidityPerTick = p.liquidityPerTick(pData);

            _updateClaimableFees(pData, feeRate, liquidityPerTick);
            _updatePosition(
                p,
                pData,
                collateral,
                contracts,
                l.marketPrice,
                false
            );
        }

        // Adjust tick deltas
        // ToDo : Implement

        ///////////////////////////////////////////////

        //        if (p.upper > l.marketPrice && isBuy)
        //            revert Pool__BuyPositionBelowMarketPrice();
        //        if (p.lower > l.marketPrice && !isBuy)
        //            revert Pool__SellPositionAboveMarketPrice();
        //
        //        // ToDo : Transfer token (Collateral or contract) -> Need first to figure out token ids structure / decimals normalization
        //        //    agent.transfer_from(
        //        //    position.collateral,
        //        //    position.contracts if position.side == RangeSide.SELL else Decimal('0'),
        //        //    position.contracts if position.side == RangeSide.BUY else Decimal('0'),
        //        //    self,
        //        //    )
        //
        //        _updatePosition(p, liqUpdate, false);
        //        Position.Data storage pData = l.positions[p.keyHash()];
        //
        //        if ((isBuy && p.lower >= l.tick) || (!isBuy && p.upper > l.tick)) {
        //            l.liquidityRate += p.phi(pData, minTickDistance);
        //        }
        //
        //        _insertTick(p, pData, left, right);
    }

    /**
     * @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
     * @param p The position key
     * @param liqUpdate The liquidity amounts to subtract
     */
    function _withdraw(
        Position.Key memory p,
        Position.Liquidity memory liqUpdate
    ) internal {
        // ToDo : Update
        //        PoolStorage.Layout storage l = PoolStorage.layout();
        //
        //        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();
        //
        //        Position.Data storage pData = l.positions[p.keyHash()];
        //        Position.Liquidity memory pLiq = _calculatePositionLiquidity(p, pData);
        //
        //        if (
        //            pLiq.collateral < liqUpdate.collateral ||
        //            pLiq.long < liqUpdate.long ||
        //            pLiq.short < liqUpdate.short
        //        ) revert Pool__InsufficientWithdrawableBalance();
        //
        //        // Ensure ticks exists
        //        if (!l.tickIndex.nodeExists(p.lower)) revert Pool__TickNotFound();
        //        if (!l.tickIndex.nodeExists(p.upper)) revert Pool__TickNotFound();
        //
        //        _updatePosition(p, liqUpdate, true);
        //
        //        bool isBuy = p.rangeSide == Position.Side.BUY;
        //        if ((isBuy && p.lower >= l.tick) || (!isBuy && p.upper > l.tick)) {
        //            l.liquidityRate -= p.phi(pData, l.minTickDistance());
        //        }
        //
        //        _removeTick(p, pData, l.marketPrice);
        //
        //        // ToDo : Transfer token (Collateral or contract) -> Need first to figure out token ids structure / decimals normalization
        //        //    agent.transfer_to(liquidity.collateral, liquidity.long, liquidity.short, self)
    }

    /**
     * @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
     * @param tradeSide Whether the taker is buying or selling
     * @param size The number of contracts being traded
     * @return The premium paid or received by the taker for the trade
     */
    function _trade(
        address owner,
        address operator,
        Position.Side tradeSide,
        uint256 size
    ) internal returns (uint256) {
        // ToDo : Check operator is approved
        //        PoolStorage.Layout storage l = PoolStorage.layout();
        //
        //        if (size == 0) revert Pool__ZeroSize();
        //        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();
        //
        //        bool isBuy = tradeSide == Position.Side.BUY;
        //
        //        Pricing.Args memory curve = Pricing.fromPool(l, tradeSide);
        //
        //        uint256 totalPremium;
        //        while (size > 0) {
        //            uint256 maxSize = curve.maxTradeSize(l.marketPrice);
        //
        //            {
        //                uint256 tradeSize = Math.min(size, maxSize);
        //
        //                uint256 nextMarketPrice;
        //                if (tradeSize != maxSize) {
        //                    nextMarketPrice = curve.nextPrice(l.marketPrice, tradeSize);
        //                } else {
        //                    nextMarketPrice = isBuy ? curve.upper : curve.lower;
        //                }
        //
        //                uint256 quotePrice = Math.average(l.marketPrice, nextMarketPrice);
        //
        //                uint256 premium = quotePrice.mulWad(tradeSize);
        //                uint256 takerFee = _takerFee(tradeSize, premium);
        //                uint256 takerPremium = premium + takerFee;
        //
        //                // Update price and liquidity variables
        //                uint256 protocolFee = (takerFee * PROTOCOL_FEE_RATE) /
        //                    INVERSE_BASIS_POINT;
        //                uint256 makerRebate = takerFee - protocolFee;
        //
        //                l.globalFeeRate += makerRebate.divWad(l.liquidityRate);
        //                totalPremium += isBuy ? takerPremium : premium;
        //
        //                l.marketPrice = nextMarketPrice;
        //                l.protocolFees += protocolFee;
        //
        //                size -= tradeSize;
        //            }
        //
        //            if (size > 0) {
        //                // The trade will require crossing into the next tick range
        //                if (isBuy) {
        //                    uint256 lower = curve.upper;
        //                    l.tick = lower;
        //                    curve.lower = curve.upper;
        //                    curve.upper = l.tickIndex.getNextNode(lower);
        //                }
        //
        //                Tick.Data memory currentTick = l.ticks[l.tick];
        //                l.liquidityRate = l.liquidityRate.add(currentTick.delta);
        //                l.ticks[l.tick] = currentTick.cross(l.globalFeeRate);
        //
        //                if (!isBuy) {
        //                    uint256 lower = l.tickIndex.getPreviousNode(curve.lower);
        //                    l.tick = lower;
        //                    curve.upper = curve.lower;
        //                    curve.lower = lower;
        //                }
        //            }
        //        }
        //
        //        Position.Liquidity storage existingPosition = l.externalPositions[
        //            owner
        //        ][operator];
        //        if (isBuy) {
        //            // ToDo : Transfer tokens
        //            // operator.transfer_from(total_premium)
        //
        //            if (existingPosition.short < size) {
        //                // ToDo : Transfer tokens
        //                // operator.transfer_to(existing_position.short)
        //                existingPosition.long += size - existingPosition.short;
        //                existingPosition.short = 0;
        //            } else {
        //                // ToDo : Transfer tokens
        //                // operator.transfer_to(size)
        //                existingPosition.short -= size;
        //            }
        //        } else {
        //            // ToDo : Transfer tokens
        //            // operator.transfer_to(total_premium)
        //
        //            if (existingPosition.long < size) {
        //                // ToDo : Transfer tokens
        //                // operator.transfer_from(size - existing_position.long)
        //                existingPosition.short += size - existingPosition.long;
        //                existingPosition.long = 0;
        //            } else {
        //                // ToDo : Transfer tokens
        //                // operator.transfer_from(size)
        //                existingPosition.long -= size;
        //            }
        //        }
        //
        //        return totalPremium;
        return 0;
    }

    /**
     * @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
     *         NOTE: This function can be called post or prior to expiration.
     */
    function _annihilate(uint256 amount) internal {
        // ToDo : Transfer long and short to pool
        // ToDo : Transfer collateral to msg.sender
    }

    /**
     * @notice Transfer an LP position to another owner.
     *         NOTE: This function can be called post or prior to expiration.
     * @param p The position key
     * @param liq The amount of each type of liquidity to transfer
     * @param newOwner The new owner of the transferred liquidity
     * @param newOperator The new operator of the transferred liquidity
     */
    function _transferPosition(
        Position.Key memory p,
        Position.Liquidity memory liq,
        address newOwner,
        address newOperator
    ) internal {
        if (liq.long > 0 && liq.short > 0)
            revert Pool__CantTransferLongAndShort();
        // ToDo : Update
        //        _updatePosition(p, liq, true);
        // ToDo : Update
        //        _updatePosition(
        //            Position.Key(newOwner, newOperator, p.rangeSide, p.lower, p.upper),
        //            liq,
        //            false
        //        );
    }

    /**
     * @notice Transfer an external trade position to another user.
     *         NOTE: This function can be called post or prior to expiration
     * @param owner The current owner of the external option contracts
     * @param operator The current operator of the external option contracts
     * @param newOwner The new owner of the transferred liquidity
     * @param newOperator The new operator of the transferred liquidity
     * @param long The amount of long option contracts to transfer
     * @param short The amount of short option contracts to transfer
     */
    function _transferTrade(
        address owner,
        address operator,
        address newOwner,
        address newOperator,
        uint256 long,
        uint256 short
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        Position.Liquidity storage existingPosition = l.externalPositions[
            owner
        ][operator];

        if (existingPosition.long < long || existingPosition.short < short)
            revert Pool__InsufficientContracts();

        existingPosition.long -= long;
        existingPosition.short -= short;

        l.externalPositions[newOwner][newOperator].long += long;
        l.externalPositions[newOwner][newOperator].short += short;
    }

    function _calculateExerciseValue(PoolStorage.Layout storage l, uint256 size)
        internal
        view
        returns (uint256)
    {
        if (size == 0) revert Pool__ZeroSize();
        if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();

        uint256 spot = l.getSpotPrice();

        int256 w = 2 * (l.isCallPool ? int256(1) : int256(0)) - 1;
        int256 wSpotStrike = w * (int256(spot) - int256(l.strike));

        uint256 exerciseValue = wSpotStrike > 0
            ? size.mulWad(uint256(wSpotStrike))
            : 0;

        if (l.isCallPool) {
            exerciseValue = exerciseValue.divWad(spot);
        }

        return exerciseValue;
    }

    function _calculateCollateralValue(
        PoolStorage.Layout storage l,
        uint256 size,
        uint256 exerciseValue
    ) internal view returns (uint256) {
        return
            l.isCallPool
                ? size - exerciseValue
                : size.mulWad(l.strike) - exerciseValue;
    }

    /**
     * @notice Exercises all long options held by an `owner`, ignoring automatic settlement fees.
     * @param owner The owner of the external option contracts
     * @param operator The operator of the position
     */
    function _exercise(address owner, address operator)
        internal
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 size = l.externalPositions[owner][operator].long;

        uint256 exerciseValue = _calculateExerciseValue(l, size);

        // ToDo : Transfer tokens
        // operator.transfer_to(exercise_value)
        l.externalPositions[owner][operator].long = 0;

        return exerciseValue;
    }

    /**
     * @notice Settles all short options held by an `owner`, ignoring automatic settlement fees.
     * @param owner The owner of the external option contracts
     * @param operator The operator of the position
     */
    function _settle(address owner, address operator)
        internal
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 size = l.externalPositions[owner][operator].short;

        uint256 exerciseValue = _calculateExerciseValue(l, size);
        uint256 collateralValue = _calculateCollateralValue(
            l,
            size,
            exerciseValue
        );

        // ToDo : Transfer tokens
        // operator.transfer_to(collateral_value)
        l.externalPositions[owner][operator].short = 0;

        return collateralValue;
    }

    /**
     * @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
     * @param p The position key
     */
    function _settlePosition(Position.Key memory p) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();

        Position.Data storage pData = l.positions[p.keyHash()];

        // ToDo : Update
        //        _updatePosition(p, Position.Liquidity(0, 0, 0), false);

        uint256 exerciseAmount = _calculateExerciseValue(l, 1e18);
        uint256 collateralAmount = _calculateCollateralValue(
            l,
            1e18,
            exerciseAmount
        );

        Position.Liquidity memory pLiq = _calculatePositionLiquidity(p, pData);
        uint256 collateral = pLiq.collateral +
            pLiq.long.mulWad(exerciseAmount) +
            pLiq.short.mulWad(collateralAmount);

        address feeClaimer = p.operator == address(0) ? p.operator : p.owner;
        // ToDo : Transfer token
        // fee_claimer.transfer_to(collateral)

        pData.collateral = 0;
        pData.contracts = 0;

        return collateral;
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

    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////

    ////////////////
    // TickSystem //
    ////////////////

    /**
     * @notice Gets the nearest tick that is less than or equal to `price`.
     */
    function _getNearestTickBelow(uint256 price) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 left = l.currentTick;

        while (left > 0 && left > price) {
            left = l.tickIndex.getPreviousNode(left);
        }

        while (left < LinkedList.MAX_UINT256 && left <= price) {
            left = l.tickIndex.getNextNode(left);
        }

        if (left == 0 || left == LinkedList.MAX_UINT256)
            revert Pool__TickNotFound();

        return left;
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
        _verifyTickWidth(price);

        if (price < Pricing.MIN_TICK_PRICE || price > Pricing.MAX_TICK_PRICE)
            revert Pool__TickOutOfRange();

        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.nodeExists(price)) return l.ticks[price];

        tick = Tick.Data(
            price,
            0,
            price <= l.marketPrice ? l.globalFeeRate : 0
        );

        l.ticks[price] = tick;
    }

    function _removeTickIfNotActive(uint256 price) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (!l.tickIndex.nodeExists(price)) return;

        Tick.Data storage tick = l.ticks[price];

        if (
            price > Pricing.MIN_TICK_PRICE &&
            price < Pricing.MAX_TICK_PRICE &&
            tick.delta == 0
        ) {
            if (price == l.currentTick) {
                uint256 newCurrentTick = l.tickIndex.getPreviousNode(price);

                if (newCurrentTick < Pricing.MIN_TICK_PRICE)
                    revert Pool__TickOutOfRange();

                l.currentTick = newCurrentTick;
            }

            l.tickIndex.remove(price);
            delete l.ticks[price];
        }
    }

    function _updateTickDeltas(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice,
        uint256 delta
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        Tick.Data storage lowerTick = l.ticks[lower];
        Tick.Data storage upperTick = l.ticks[upper];

        int256 _delta = int256(delta);
        if (upper <= l.currentTick) {
            lowerTick.delta -= _delta;
            upperTick.delta += _delta;
        } else if (lower > l.currentTick) {
            lowerTick.delta += _delta;
            upperTick.delta -= _delta;
        } else {
            lowerTick.delta -= _delta;
            upperTick.delta -= _delta;
            l.liquidityRate += delta;
        }

        // Reconcile current tick with system
        // Check if deposit or withdrawal
        if (delta > 0) {
            while (l.tickIndex.getNextNode(l.currentTick) < marketPrice) {
                _cross(Position.Side.BUY);
            }
        } else {
            _removeTickIfNotActive(lower);
            _removeTickIfNotActive(upper);
        }
    }

    function _updateGlobalFeeRate(PoolStorage.Layout storage l, uint256 amount)
        internal
    {
        if (l.liquidityRate == 0) return;
        l.globalFeeRate += amount.divWad(l.liquidityRate);
    }

    function _cross(Position.Side side) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (side == Position.Side.BUY) {
            uint256 right = l.tickIndex.getNextNode(l.currentTick);
            if (right >= Pricing.MAX_TICK_PRICE) revert Pool__TickOutOfRange();
            l.currentTick = right;
        }

        Tick.Data storage currentTick = l.ticks[l.currentTick];

        l.liquidityRate = l.liquidityRate.add(currentTick.delta);

        // Flip the tick
        currentTick.delta = -currentTick.delta;

        currentTick.externalFeeRate =
            l.globalFeeRate -
            currentTick.externalFeeRate;

        if (side == Position.Side.SELL) {
            if (l.currentTick <= Pricing.MIN_TICK_PRICE)
                revert Pool__TickOutOfRange();
            l.currentTick = l.tickIndex.getPreviousNode(l.currentTick);
        }
    }
}
