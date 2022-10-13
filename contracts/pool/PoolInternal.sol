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
    using Position for Position.Key;
    using PricingCurve for PricingCurve.Args;
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
     * @param k The position key
     * @param left The normalized price of the left Tick for a new position.
     * @param right The normalized price of the right Tick for a new position.
     */
    function _insertTick(
        Position.Key memory k,
        Position.Data memory pData,
        uint256 left,
        uint256 right
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 lower = k.lower;
        uint256 upper = k.upper;

        if (
            left > lower ||
            l.tickIndex.getNextNode(left) < lower ||
            right < upper ||
            l.tickIndex.getPreviousNode(right) > upper ||
            left == right ||
            lower == upper
        ) revert Pool__TickInsertInvalid();

        int256 delta = k.phi(pData, l.minTickDistance()).toInt256();

        if (k.rangeSide == PoolStorage.Side.SELL) {
            l.ticks[lower].delta += delta;
            l.ticks[upper].delta -= delta;
        } else {
            l.ticks[lower].delta -= delta;
            l.ticks[upper].delta += delta;
        }

        if (left != lower) {
            if (l.tickIndex.insertAfter(left, lower) == false)
                revert Pool__TickInsertFailed();

            if (k.rangeSide == PoolStorage.Side.SELL) {
                if (lower == l.marketPrice) {
                    l.liquidityRate = l.liquidityRate.addInt256(
                        l.ticks[lower].delta
                    );
                    l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);

                    if (l.tick < lower) l.tick = lower;
                }
            } else {
                l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
            }
        }

        if (right != upper) {
            if (l.tickIndex.insertBefore(right, upper) == false)
                revert Pool__TickInsertFailed();

            if (k.rangeSide == PoolStorage.Side.BUY) {
                if (l.tick <= upper) {
                    l.liquidityRate = l.liquidityRate.addInt256(
                        l.ticks[upper].delta
                    );
                }
                l.ticks[upper] = l.ticks[upper].cross(l.globalFeeRate);

                if (l.tick < lower) {
                    l.tick = lower;
                }
            }
        }
    }

    /**
     * @notice Removes liquidity from a pair of Ticks and if necessary, removes
     *         the Tick(s) from the doubly-linked Tick list.
     * @param k The position key
     * @param marketPrice The normalized market price
     */
    function _removeTick(
        Position.Key memory k,
        Position.Data memory pData,
        uint256 marketPrice
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 lower = k.lower;
        uint256 upper = k.upper;

        int256 phi = k.phi(pData, l.minTickDistance()).toInt256();
        bool leftRangeSide = k.rangeSide == PoolStorage.Side.BUY;
        bool rightRangeSide = k.rangeSide == PoolStorage.Side.SELL;

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

        // ToDo : Add internal function for those checks ?
        if (size == 0) revert Pool__ZeroSize();
        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

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

    function _getClaimableFees(Position.Key memory k)
        internal
        view
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[k.keyHash()];

        uint256 feeGrowthRate = _calculatePositionGrowth(k.lower, k.upper);

        return
            (feeGrowthRate - pData.lastFeeRate).mulWad(
                k.phi(pData, l.minTickDistance())
            );
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
    function _calculatePositionLiquidity(
        Position.Key memory p,
        Position.Data memory pData
    ) internal view returns (Position.Liquidity memory pLiq) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 marketPrice = l.marketPrice;
        uint256 transitionPrice = p.transitionPrice(pData);

        if (p.rangeSide == PoolStorage.Side.BUY) {
            if (marketPrice <= p.lower) {
                pLiq.collateral = pData.contracts;
                pLiq.long = (pData.collateral -
                    Math.mean(p.upper, transitionPrice).mulWad(pData.contracts))
                    .divWad(Math.mean(transitionPrice, p.lower));
            } else if (marketPrice > p.upper) {
                pLiq.collateral = pData.collateral;
                pLiq.short = pData.contracts;
            } else {
                if (marketPrice >= p.upper) {
                    pLiq.collateral +=
                        pData.collateral -
                        pData.contracts.mulWad(Math.mean(p.upper, marketPrice));

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
                            Math.mean(p.upper, transitionPrice)
                        ) -
                        Math.mean(transitionPrice, p.lower).mulWad(
                            pData.collateral -
                                pData.contracts.mulWad(
                                    Math.mean(p.upper, transitionPrice)
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
                    Math.mean(p.lower, transitionPrice)
                );
                pLiq.short = pData.collateral;
            } else {
                pLiq.collateral += pData.contracts.mulWad(
                    Math.mean(p.lower, Math.max(marketPrice, transitionPrice))
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

    function _updatePosition(
        Position.Key memory k,
        Position.Liquidity memory liqUpdate,
        bool subtract
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 feeGrowthRate = _calculatePositionGrowth(k.lower, k.upper);
        Position.Data storage pData = l.positions[k.keyHash()];

        uint256 contracts = liqUpdate.short + liqUpdate.long;

        if (liqUpdate.collateral > 0 || contracts > 0) {
            if (subtract) {
                if (pData.collateral < liqUpdate.collateral)
                    revert Pool__InsufficientCollateral();
                if (pData.contracts < contracts)
                    revert Pool__InsufficientContracts();

                pData.collateral -= liqUpdate.collateral;
                pData.contracts -= contracts;
            } else {
                pData.collateral += liqUpdate.collateral;
                pData.contracts += contracts;
            }
        }

        pData.claimableFees +=
            (feeGrowthRate - pData.lastFeeRate) *
            k.phi(pData, l.minTickDistance());
        pData.lastFeeRate = feeGrowthRate;
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
     * @param k The position key
     * @param liqUpdate The liquidity amounts to add
     * @param left The normalized price of the tick at the left of the position
     * @param right The normalized price of the tick at th right of the position
     */
    function _deposit(
        Position.Key memory k,
        Position.Liquidity memory liqUpdate,
        uint256 left,
        uint256 right
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 minTickDistance = l.minTickDistance();
        _verifyTickWidth(k.lower, minTickDistance);
        _verifyTickWidth(k.upper, minTickDistance);

        bool isBuy = k.rangeSide == PoolStorage.Side.BUY;

        if (k.upper > l.marketPrice && isBuy)
            revert Pool__BuyPositionBelowMarketPrice();
        if (k.lower > l.marketPrice && !isBuy)
            revert Pool__SellPositionAboveMarketPrice();

        // ToDo : Transfer token (Collateral or contract) -> Need first to figure out token ids structure / decimals normalization
        //    agent.transfer_from(
        //    position.collateral,
        //    position.contracts if position.side == RangeSide.SELL else Decimal('0'),
        //    position.contracts if position.side == RangeSide.BUY else Decimal('0'),
        //    self,
        //    )

        _updatePosition(k, liqUpdate, false);
        Position.Data storage pData = l.positions[k.keyHash()];

        if ((isBuy && k.lower >= l.tick) || (!isBuy && k.upper > l.tick)) {
            l.liquidityRate += k.phi(pData, minTickDistance);
        }

        _insertTick(k, pData, left, right);
    }

    /**
     * @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
     * @param k The position key
     * @param liqUpdate The liquidity amounts to subtract
     */
    function _withdraw(
        Position.Key memory k,
        Position.Liquidity memory liqUpdate
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

        Position.Data storage pData = l.positions[k.keyHash()];
        Position.Liquidity memory pLiq = _calculatePositionLiquidity(k, pData);

        if (
            pLiq.collateral < liqUpdate.collateral ||
            pLiq.long < liqUpdate.long ||
            pLiq.short < liqUpdate.short
        ) revert Pool__InsufficientWithdrawableBalance();

        // Ensure ticks exists
        if (!l.tickIndex.nodeExists(k.lower)) revert Pool__TickNotFound();
        if (!l.tickIndex.nodeExists(k.upper)) revert Pool__TickNotFound();

        _updatePosition(k, liqUpdate, true);

        bool isBuy = k.rangeSide == PoolStorage.Side.BUY;
        if ((isBuy && k.lower >= l.tick) || (!isBuy && k.upper > l.tick)) {
            l.liquidityRate -= k.phi(pData, l.minTickDistance());
        }

        _removeTick(k, pData, l.marketPrice);

        // ToDo : Transfer token (Collateral or contract) -> Need first to figure out token ids structure / decimals normalization
        //    agent.transfer_to(liquidity.collateral, liquidity.long, liquidity.short, self)
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
        PoolStorage.Side tradeSide,
        uint256 size
    ) internal returns (uint256) {
        // ToDo : Check operator is approved
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (size == 0) revert Pool__ZeroSize();
        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

        bool isBuy = tradeSide == PoolStorage.Side.BUY;

        PricingCurve.Args memory curve = PricingCurve.fromPool(l, tradeSide);

        uint256 totalPremium;
        while (size > 0) {
            uint256 maxSize = curve.maxTradeSize(l.marketPrice);
            uint256 tradeSize = Math.min(size, maxSize);

            uint256 nextMarketPrice;
            if (tradeSize != maxSize) {
                nextMarketPrice = curve.nextPrice(l.marketPrice, tradeSize);
            } else {
                nextMarketPrice = isBuy ? curve.upper : curve.lower;
            }

            uint256 quotePrice = Math.mean(l.marketPrice, nextMarketPrice);

            uint256 premium = quotePrice.mulWad(tradeSize);
            uint256 takerFee = _takerFee(tradeSize, premium);
            uint256 takerPremium = premium + takerFee;

            // Update price and liquidity variables
            uint256 protocolFee = (takerFee * PROTOCOL_FEE_RATE) /
                INVERSE_BASIS_POINT;
            uint256 makerRebate = takerFee - protocolFee;

            l.globalFeeRate += makerRebate.divWad(l.liquidityRate);
            totalPremium += isBuy ? takerPremium : premium;

            l.marketPrice = nextMarketPrice;
            l.protocolFees += protocolFee;

            size -= tradeSize;
            if (size > 0) {
                // The trade will require crossing into the next tick range
                if (isBuy) {
                    uint256 lower = curve.upper;
                    l.tick = lower;
                    curve.lower = curve.upper;
                    curve.upper = l.tickIndex.getNextNode(lower);
                }

                Tick.Data memory currentTick = l.ticks[l.tick];
                l.liquidityRate = l.liquidityRate.addInt256(currentTick.delta);
                l.ticks[l.tick] = currentTick.cross(l.globalFeeRate);

                if (!isBuy) {
                    uint256 lower = l.tickIndex.getPreviousNode(curve.lower);
                    l.tick = lower;
                    curve.upper = curve.lower;
                    curve.lower = lower;
                }
            }
        }

        Position.Liquidity storage existingPosition = l.externalPositions[
            owner
        ][operator];
        if (isBuy) {
            // ToDo : Transfer tokens
            // operator.transfer_from(total_premium)

            if (existingPosition.short < size) {
                // ToDo : Transfer tokens
                // operator.transfer_to(existing_position.short)
                existingPosition.long += size - existingPosition.short;
                existingPosition.short = 0;
            } else {
                // ToDo : Transfer tokens
                // operator.transfer_to(size)
                existingPosition.short -= size;
            }
        } else {
            // ToDo : Transfer tokens
            // operator.transfer_to(total_premium)

            if (existingPosition.long < size) {
                // ToDo : Transfer tokens
                // operator.transfer_from(size - existing_position.long)
                existingPosition.short += size - existingPosition.long;
                existingPosition.long = 0;
            } else {
                // ToDo : Transfer tokens
                // operator.transfer_from(size)
                existingPosition.long -= size;
            }
        }

        return totalPremium;
    }

    /**
     * @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
     *         NOTE: This function can be called post or prior to expiration.
     */
    function _annihilate(uint256 amount) internal {
        // ToDo : Transfer long and short to pool
        // ToDo : Transfer collateral to msg.sender
    }

    function _transferPosition() internal {
        // ToDo : Implement
    }

    function _transferTrade() internal {
        // ToDo : Implement
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
     * @param k The position key
     */
    function _settlePosition(Position.Key memory k) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();

        Position.Data storage pData = l.positions[k.keyHash()];

        _updatePosition(k, Position.Liquidity(0, 0, 0), false);

        uint256 exerciseAmount = _calculateExerciseValue(l, 1e18);
        uint256 collateralAmount = _calculateCollateralValue(
            l,
            1e18,
            exerciseAmount
        );

        Position.Liquidity memory pLiq = _calculatePositionLiquidity(k, pData);
        uint256 collateral = pLiq.collateral +
            pLiq.long.mulWad(exerciseAmount) +
            pLiq.short.mulWad(collateralAmount);

        address feeClaimer = k.operator == address(0) ? k.operator : k.owner;
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
}
