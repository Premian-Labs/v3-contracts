// SPDX-License-Identifier: UNLICENSED

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

            return;
        }

        // Convert position to opposite side to make it modifiable
        pData.collateral = isBuy
            ? p.liquidity(pData).mulWad(p.averagePrice())
            : pData.contracts;
        pData.contracts = isBuy
            ? pData.collateral
            : p.liquidity(pData).mulWad(p.averagePrice());
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

        // ToDo : implement
        // Transfer funds from the LP to the pool
        /*
        info.owner.transfer_from(
            order.collateral,
            order.contracts if side == TradeSide.SELL else Decimal("0"),
            order.contracts if side == TradeSide.BUY else Decimal("0"),
            self
        )
        */

        Position.Data storage pData = l.positions[p.keyHash()];

        uint256 feeRate;
        {
            // If ticks dont exist they are created and inserted into the linked list
            Tick.Data memory lowerTick = _getOrCreateTick(p.lower);
            Tick.Data memory upperTick = _getOrCreateTick(p.upper);

            feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );
        }

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
        uint256 delta = p.liquidityPerTick(pData) - liquidityPerTick;
        _updateTickDeltas(p.lower, p.upper, l.marketPrice, delta);
    }

    /**
     * @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
     * @param p The position key
     * @param collateral The amount of collateral to be deposited
     * @param contracts The amount of contracts to be deposited
     */
    function _withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 contracts
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        Position.Data storage pData = l.positions[p.keyHash()];

        if (pData.contracts + pData.collateral == 0)
            revert Pool__PositionDoesNotExist();

        Tick.Data memory lowerTick = _getOrCreateTick(p.lower);
        Tick.Data memory upperTick = _getOrCreateTick(p.upper);

        // Initialize variables before position update
        uint256 liquidityPerTick = p.liquidityPerTick(pData);
        uint256 feeRate = _rangeFeeRate(
            l,
            p.lower,
            p.upper,
            lowerTick.externalFeeRate,
            upperTick.externalFeeRate
        );
        uint256 short = p.short(pData, l.marketPrice);
        uint256 long = p.long(pData, l.marketPrice);

        // Update claimable fees
        _updateClaimableFees(pData, feeRate, liquidityPerTick);

        // Adjust position to correspond with the side of the order
        _updatePosition(p, pData, collateral, contracts, l.marketPrice, true);

        // ToDo : Implement
        // Transfer funds from the pool back to the LP
        /*
                # Transfer funds from the pool back to the LP
        info.owner.transfer_to(
            collateral=order.collateral,
            long=order.contracts if long > 0 else Decimal("0"),
            short=order.contracts if short > 0 else Decimal("0"),
            pool=self
        )
        */

        // Adjust tick deltas (reverse of deposit)
        uint256 delta = p.liquidityPerTick(pData) - liquidityPerTick;
        _updateTickDeltas(p.lower, p.upper, l.marketPrice, delta);
    }

    /**
     * @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
     * @param side Whether the taker is buying or selling
     * @param size The number of contracts being traded
     * @return The premium paid or received by the taker for the trade
     */
    function _trade(
        address owner,
        address operator,
        Position.Side side,
        uint256 size
    ) internal returns (uint256) {
        // ToDo : Check operator is approved
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (size == 0) revert Pool__ZeroSize();
        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();

        bool isBuy = side == Position.Side.BUY;

        Pricing.Args memory pricing = Pricing.fromPool(l, side);

        uint256 totalPremium;
        uint256 remaining = size;

        while (remaining > 0) {
            uint256 maxSize = pricing.maxTradeSize();
            uint256 tradeSize = Math.min(remaining, maxSize);

            {
                uint256 nextMarketPrice;
                if (tradeSize != maxSize) {
                    nextMarketPrice = pricing.nextPrice(tradeSize);
                } else {
                    nextMarketPrice = isBuy ? pricing.upper : pricing.lower;
                }

                uint256 quotePrice = Math.average(
                    l.marketPrice,
                    nextMarketPrice
                );

                uint256 premium = quotePrice.mulWad(tradeSize);
                uint256 takerFee = _takerFee(tradeSize, premium);

                // Update price and liquidity variables
                uint256 protocolFee = (takerFee * PROTOCOL_FEE_RATE) /
                    INVERSE_BASIS_POINT;
                uint256 makerRebate = takerFee - protocolFee;

                _updateGlobalFeeRate(l, makerRebate);

                // is_buy: taker has to pay premium + fees
                // ~is_buy: taker receives premium - fees
                totalPremium += isBuy ? premium + takerFee : premium - takerFee;

                l.marketPrice = nextMarketPrice;
                l.protocolFees += protocolFee;
            }

            if (tradeSize < remaining) {
                // The trade will require crossing into the next tick range
                if (
                    isBuy &&
                    l.tickIndex.getNextNode(l.currentTick) >=
                    Pricing.MAX_TICK_PRICE
                ) revert Pool__InsufficientAskLiquidity();

                if (!isBuy && l.currentTick <= Pricing.MIN_TICK_PRICE)
                    revert Pool__InsufficientBidLiquidity();
            }

            remaining -= tradeSize;
        }

        Position.Liquidity storage externalPosition = l.externalPositions[
            owner
        ][operator];

        // ToDo : Implement
        /*
         # update the agent's liquidity state
        update_liquidity_and_operator_post_trade(
            operator=agent,
            total_premium=total_premium,
            pool=self,
            side=side,
            size=size
        )
        */

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

        // ToDo : Mint tokens

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
        uint256 strike = l.strike;
        bool isCall = l.isCallPool;

        uint256 intrinsicValue;
        if (isCall && spot > strike) {
            intrinsicValue = spot - strike;
        } else if (!isCall && spot < strike) {
            intrinsicValue = strike - spot;
        } else {
            return 0;
        }

        uint256 exerciseValue = size.mulWad(intrinsicValue);

        if (isCall) {
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

        Tick.Data memory lowerTick = _getOrCreateTick(p.lower);
        Tick.Data memory upperTick = _getOrCreateTick(p.upper);

        {
            // Update claimable fees
            uint256 feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );

            _updateClaimableFees(pData, feeRate, p.liquidityPerTick(pData));
        }

        // using the market price here is okay as the market price cannot be
        // changed through trades / deposits / withdrawals post-maturity.
        // changes to the market price are halted. thus, the market price
        // determines the amount of ask.
        // obviously, if the market was still liquid, the market price at
        // maturity should be close to the intrinsic value.

        uint256 price = l.marketPrice;
        uint256 payoff = _calculateExerciseValue(l, 1e18);

        uint256 collateral = p.bid(pData, price) +
            p.ask(pData, price) +
            p.long(pData, price).mulWad(payoff) +
            p.short(pData, price).mulWad(
                (l.isCallPool ? 1e18 : l.strike) - payoff
            ) +
            pData.claimableFees;

        // ToDo : Implement
        // position.operator.transfer_to(collateral)

        pData.collateral = 0;
        pData.contracts = 0;
        pData.claimableFees = 0;

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
    // ToDo : Reorganize those functions ?

    /**
     * @notice Gets the nearest tick that is less than or equal to `price`.
     */
    function _getNearestTickBelow(uint256 price)
        internal
        view
        returns (uint256)
    {
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

        uint256 left = _getNearestTickBelow(price);
        l.tickIndex.insertAfter(left, price);
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

    /**
     * @notice Calculates the growth and exposure change between the lower
     *    and upper Ticks of a Position.
     *
     *                     l         ▼         u
     *    ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     *    => (global - external(l) - external(u))
     *
     *                ▼    l                   u
     *    ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     *    => (global - (global - external(l)) - external(u))
     *
     *                     l                   u    ▼
     *    ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
     *    => (global - external(l) - (global - external(u)))
     */
    function _rangeFeeRate(
        PoolStorage.Layout storage l,
        uint256 lower,
        uint256 upper,
        uint256 lowerTickExternalFeeRate,
        uint256 upperTickExternalFeeRate
    ) internal view returns (uint256) {
        uint256 aboveFeeRate = l.currentTick >= upper
            ? l.globalFeeRate - upperTickExternalFeeRate
            : upperTickExternalFeeRate;

        uint256 belowFeeRate = l.currentTick >= lower
            ? lowerTickExternalFeeRate
            : l.globalFeeRate - lowerTickExternalFeeRate;

        return l.globalFeeRate - aboveFeeRate - belowFeeRate;
    }
}
