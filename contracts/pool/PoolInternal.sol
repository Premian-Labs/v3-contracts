// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Position} from "../libraries/Position.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {Tick} from "../libraries/Tick.sol";
import {WadMath} from "../libraries/WadMath.sol";

import {IPoolInternal} from "./IPoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is IPoolInternal, ERC1155EnumerableInternal {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using Position for Position.OrderType;
    using Pricing for Pricing.Args;
    using WadMath for uint256;
    using Tick for Tick.Data;
    using SafeCast for uint256;
    using Math for int256;
    using UintUtils for uint256;

    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    uint256 private constant WAD = 1e18;

    // ToDo : Define final values
    uint256 private constant PROTOCOL_FEE_PERCENTAGE = 5e3; // 50%
    uint256 private constant PREMIUM_FEE_PERCENTAGE = 1e2; // 1%
    uint256 private constant COLLATERAL_FEE_PERCENTAGE = 1e2; // 1%

    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param size The size of a trade (number of contracts)
    /// @param premium The total cost of option(s) for a purchase
    /// @return The taker fee for an option trade
    function _takerFee(
        uint256 size,
        uint256 premium
    ) internal pure returns (uint256) {
        uint256 premiumFee = (premium * PREMIUM_FEE_PERCENTAGE) /
            INVERSE_BASIS_POINT;
        // 3% of premium
        uint256 notionalFee = (size * COLLATERAL_FEE_PERCENTAGE) /
            INVERSE_BASIS_POINT;
        // 0.3% of notional
        return Math.max(premiumFee, notionalFee);
    }

    function _getQuote(
        uint256 size,
        bool isBuy
    ) internal view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(size);
        _ensureNotExpired(l);

        Pricing.Args memory pricing = Pricing.Args(
            l.liquidityRate,
            l.marketPrice,
            l.currentTick,
            l.tickIndex.next(l.currentTick),
            isBuy
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
                uint256 takerFee = Position.contractsToCollateral(
                    _takerFee(size, premium),
                    l.strike,
                    l.isCallPool
                );

                // Denormalize premium
                premium = Position.contractsToCollateral(
                    premium,
                    l.strike,
                    l.isCallPool
                );

                totalPremium += isBuy ? premium + takerFee : premium - takerFee;
                pricing.marketPrice = nextPrice;
            }

            // ToDo : Deal with rounding error
            if (maxSize >= size - (WAD / 10)) {
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
                    : l.tickIndex.prev(pricing.lower);
                pricing.upper = l.tickIndex.next(pricing.lower);

                // Compute new liquidity
                liquidity = pricing.liquidity();
                maxSize = pricing.maxTradeSize();
            }
        }

        return totalPremium;
    }

    /// @notice Updates the amount of fees an LP can claim for a position (without claiming).
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

    function _updateClaimableFees(
        PoolStorage.Layout storage l,
        Position.Key memory p,
        Position.Data storage pData
    ) internal {
        Tick.Data memory lowerTick = _getTick(p.lower);
        Tick.Data memory upperTick = _getTick(p.upper);

        _updateClaimableFees(
            pData,
            _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            ),
            p.liquidityPerTick(
                _balanceOf(
                    p.owner,
                    PoolStorage.formatTokenId(
                        p.operator,
                        p.lower,
                        p.upper,
                        p.orderType
                    )
                )
            )
        );
    }

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    function _claim(
        Position.Key memory p
    ) internal returns (uint256 claimedFees) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[p.keyHash()];
        _updateClaimableFees(l, p, pData);
        claimedFees = pData.claimableFees;

        pData.claimableFees = 0;
        IERC20(l.getPoolToken()).transfer(p.operator, claimedFees);
    }

    function _verifyTickWidth(uint256 price) internal pure {
        if (price % Pricing.MIN_TICK_DISTANCE != 0)
            revert Pool__TickWidthInvalid();
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param orderType The order type
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param collateral The amount of collateral to be deposited
    /// @param longs The amount of longs to be deposited
    /// @param shorts The amount of shorts to be deposited
    function _deposit(
        Position.Key memory p,
        Position.OrderType orderType,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) internal {
        bool isBuy = orderType.isLeft();

        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(collateral + longs + shorts);
        if (longs > 0 && shorts > 0) revert Pool__LongOrShortMustBeZero();
        _ensureNotExpired(l);

        p.strike = l.strike;
        p.isCall = l.isCallPool;

        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        // Fix for if stranded market price
        if (
            l.liquidityRate == 0 &&
            p.lower >= l.currentTick &&
            p.upper <= l.tickIndex.next(l.currentTick)
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
        if (collateral > 0) {
            IERC20(l.getPoolToken()).transferFrom(
                p.owner,
                address(this),
                collateral
            );
        }

        if (longs + shorts > 0) {
            _safeTransfer(
                address(this),
                p.owner,
                address(this),
                shorts > 0 ? PoolStorage.SHORT : PoolStorage.LONG,
                shorts > 0 ? shorts : longs,
                ""
            );
        }

        Position.Data storage pData = l.positions[p.keyHash()];

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        uint256 liquidityPerTick;
        {
            uint256 feeRate;
            {
                // If ticks dont exist they are created and inserted into the linked list
                Tick.Data memory lowerTick = _getOrCreateTick(
                    p.lower,
                    belowLower
                );
                Tick.Data memory upperTick = _getOrCreateTick(
                    p.upper,
                    belowUpper
                );

                feeRate = _rangeFeeRate(
                    l,
                    p.lower,
                    p.upper,
                    lowerTick.externalFeeRate,
                    upperTick.externalFeeRate
                );
            }

            uint256 size;
            uint256 initialSize = _balanceOf(p.owner, tokenId);

            if (initialSize > 0) {
                liquidityPerTick = p.liquidityPerTick(initialSize);

                _updateClaimableFees(pData, feeRate, liquidityPerTick);

                size = p.calculateAssetChange(
                    initialSize,
                    l.marketPrice,
                    collateral,
                    longs,
                    shorts
                );
            } else {
                size = collateral + longs + shorts;
                pData.lastFeeRate = feeRate;
            }

            _mint(
                p.owner,
                PoolStorage.formatTokenId(
                    p.operator,
                    p.lower,
                    p.upper,
                    p.orderType
                ),
                size,
                ""
            );
        }

        // Adjust tick deltas
        _updateTickDeltas(
            p.lower,
            p.upper,
            l.marketPrice,
            p.liquidityPerTick(_balanceOf(p.owner, tokenId)) - liquidityPerTick
        );
    }

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    /// @param p The position key
    /// @param collateral The amount of collateral to be withdrawn
    /// @param longs The amount of longs to be withdrawn
    /// @param shorts The amount of shorts to be withdrawn
    function _withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        if (longs > 0 && shorts > 0) revert Pool__LongOrShortMustBeZero();
        _ensureExpired(l);
        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        p.strike = l.strike;
        p.isCall = l.isCallPool;

        Position.Data storage pData = l.positions[p.keyHash()];

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        uint256 initialSize = _balanceOf(p.owner, tokenId);

        if (initialSize == 0) revert Pool__PositionDoesNotExist();

        Tick.Data memory lowerTick = _getTick(p.lower);
        Tick.Data memory upperTick = _getTick(p.upper);

        // Initialize variables before position update
        uint256 liquidityPerTick = p.liquidityPerTick(initialSize);
        {
            uint256 feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );

            // Update claimable fees
            _updateClaimableFees(pData, feeRate, liquidityPerTick);

            // Check whether it's a full withdrawal before updating the position
            uint256 price = l.marketPrice;
            bool isFullWithdrawal = p.collateral(initialSize, price) ==
                collateral &&
                p.long(initialSize, price) == longs &&
                p.short(initialSize, price) == shorts;

            // Straddled price
            // if (p.lower < price && price < p.upper) {
            //     if (!isFullWithdrawal) revert Pool__FullWithdrawalExpected();
            // }

            uint256 collateralToTransfer = collateral;

            uint256 size;
            if (isFullWithdrawal) {
                // Claim all fees and remove the position completely
                collateralToTransfer += pData.claimableFees;
                // ToDo : Emit fee claiming event

                size = initialSize;

                pData.claimableFees = 0;
                pData.lastFeeRate = 0;
            } else {
                size = p.calculateAssetChange(
                    initialSize,
                    price,
                    collateral,
                    longs,
                    shorts
                );
            }

            _burn(p.owner, tokenId, size);

            if (
                collateralToTransfer > 0
            ) // Transfer funds from the pool back to the LP
            {
                IERC20(l.getPoolToken()).transfer(
                    p.owner,
                    collateralToTransfer
                );
            }

            if (longs + shorts > 0) {
                _safeTransfer(
                    address(this),
                    address(this),
                    p.owner,
                    shorts > 0 ? PoolStorage.SHORT : PoolStorage.LONG,
                    shorts > 0 ? shorts : longs,
                    ""
                );
            }
        }

        // Adjust tick deltas (reverse of deposit)
        uint256 delta = p.liquidityPerTick(_balanceOf(p.owner, tokenId)) -
            liquidityPerTick;
        _updateTickDeltas(p.lower, p.upper, l.marketPrice, delta);

        // ToDo : Add return values ?
    }

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    /// @param size The number of contracts being traded
    /// @param isBuy Whether the taker is buying or selling
    /// @return The premium paid or received by the taker for the trade
    function _trade(
        address user,
        uint256 size,
        bool isBuy
    ) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(size);
        _ensureNotExpired(l);

        Pricing.Args memory pricing = Pricing.fromPool(l, isBuy);

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
                uint256 takerFee = Position.contractsToCollateral(
                    _takerFee(tradeSize, premium),
                    l.strike,
                    l.isCallPool
                );

                // Denormalize premium
                premium = Position.contractsToCollateral(
                    premium,
                    l.strike,
                    l.isCallPool
                );

                // Update price and liquidity variables
                uint256 protocolFee = (takerFee * PROTOCOL_FEE_PERCENTAGE) /
                    INVERSE_BASIS_POINT;
                uint256 makerRebate = takerFee - protocolFee;

                _updateGlobalFeeRate(l, makerRebate);

                // is_buy: taker has to pay premium + fees
                // ~is_buy: taker receives premium - fees
                totalPremium += isBuy ? premium + takerFee : premium - takerFee;

                l.marketPrice = nextMarketPrice;
                l.protocolFees += protocolFee;
            }

            // ToDo : Deal with rounding error
            if (maxSize >= remaining - (WAD / 10)) {
                remaining = 0;
            } else {
                // The trade will require crossing into the next tick range
                if (
                    isBuy &&
                    l.tickIndex.next(l.currentTick) >= Pricing.MAX_TICK_PRICE
                ) revert Pool__InsufficientAskLiquidity();

                if (!isBuy && l.currentTick <= Pricing.MIN_TICK_PRICE)
                    revert Pool__InsufficientBidLiquidity();

                remaining -= tradeSize;
                _cross(isBuy);
            }
        }

        _updateUserAssets(l, user, totalPremium, size, isBuy);

        return totalPremium;
    }

    /// @notice Compute the change in short / long option contracts of an agent in order to
    ///         transfer the contracts and execute a trade.=
    function _getTradeDelta(
        address user,
        uint256 size,
        bool isBuy
    ) internal view returns (int256 deltaLong, int256 deltaShort) {
        uint256 longs = _balanceOf(user, PoolStorage.LONG);
        uint256 shorts = _balanceOf(user, PoolStorage.SHORT);

        if (isBuy) {
            deltaShort = -int256(Math.min(shorts, size));
            deltaLong = int256(size) + deltaShort;
        } else {
            deltaLong = -int256(Math.min(longs, size));
            deltaShort = int256(size) + deltaLong;
        }
    }

    /// @notice Execute a trade by transferring the net change in short and long option
    ///         contracts and collateral to / from an agent.
    function _updateUserAssets(
        PoolStorage.Layout storage l,
        address user,
        uint256 totalPremium,
        uint256 size,
        bool isBuy
    ) internal {
        (int256 deltaLong, int256 deltaShort) = _getTradeDelta(
            user,
            size,
            isBuy
        );

        if (
            deltaLong == deltaShort ||
            (deltaLong > 0 && deltaShort > 0) ||
            (deltaLong < 0 && deltaShort < 0)
        ) revert Pool__InvalidAssetUpdate();

        bool _isBuy = deltaLong > 0 || deltaShort < 0;

        uint256 deltaShortAbs = Math.abs(deltaShort);
        uint256 shortCollateral = Position.contractsToCollateral(
            deltaShortAbs,
            l.strike,
            l.isCallPool
        );

        int256 deltaCollateral;
        if (deltaShort < 0) {
            deltaCollateral = _isBuy
                ? int256(shortCollateral) - int256(totalPremium)
                : int256(totalPremium);
        } else {
            deltaCollateral = _isBuy
                ? -int256(totalPremium)
                : int256(totalPremium) - int256(shortCollateral);
        }

        // Transfer collateral
        if (deltaCollateral < 0) {
            IERC20(l.getPoolToken()).transferFrom(
                user,
                address(this),
                uint256(-deltaCollateral)
            );
        } else if (deltaCollateral > 0) {
            IERC20(l.getPoolToken()).transfer(user, uint256(deltaCollateral));
        }

        // Transfer long
        if (deltaLong < 0) {
            _burn(user, PoolStorage.LONG, uint256(-deltaLong));
        } else if (deltaLong > 0) {
            _mint(user, PoolStorage.LONG, uint256(deltaLong), "");
        }

        // Transfer short
        if (deltaShort < 0) {
            _burn(user, PoolStorage.SHORT, uint256(-deltaShort));
        } else if (deltaShort > 0) {
            _mint(user, PoolStorage.SHORT, uint256(deltaShort), "");
        }
    }

    /// @notice Functionality to support the RFQ / OTC system.
    ///         An LP can create a quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    function _fillQuote(
        address user,
        uint256 size,
        TradeQuote memory quote
    ) internal {
        // ToDo : Implement checks to make sure quote is valid

        if (size > quote.size) revert Pool__AboveQuoteSize();

        if (
            Pricing.MIN_TICK_PRICE > quote.price ||
            quote.price > Pricing.MAX_TICK_PRICE
        ) revert Pool__OutOfBoundsPrice();

        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 premium = quote.price.mulWad(size);
        uint256 takerFee = Position.contractsToCollateral(
            _takerFee(size, premium),
            l.strike,
            l.isCallPool
        );

        // Denormalize premium
        premium = Position.contractsToCollateral(
            premium,
            l.strike,
            l.isCallPool
        );

        uint256 protocolFee = (takerFee * PROTOCOL_FEE_PERCENTAGE) /
            INVERSE_BASIS_POINT;
        uint256 makerRebate = takerFee - protocolFee;
        l.protocolFees += protocolFee;

        /////////////////////////
        // Process trade taker //
        /////////////////////////
        uint256 premiumTaker = !quote.isBuy
            ? premium // Taker Buying
            : premium - takerFee; // Taker selling

        _updateUserAssets(l, user, premiumTaker, size, !quote.isBuy);

        /////////////////////////
        // Process trade maker //
        /////////////////////////
        // if the maker is selling (is_buy is True) the protocol
        // if the taker is buying (is_buy is False) the maker is paying the
        // premium minus the maker fee, he will be charged the protocol fee.
        // summary:
        // is_buy:
        //         quote.premium              quote.premium - PF
        //   LT --------------------> Pool --------------------> LP
        // ~is_buy:
        //         quote.premium - TF         quote.premium - MF
        //   LT <-------------------- Pool <-------------------- LP
        //
        // note that the logic is different from the trade logic, since the
        // maker rebate gets directly transferred to the LP instead of
        // incrementing the global rate
        uint256 premiumMaker = quote.isBuy
            ? premium - makerRebate // Maker buying
            : premium - protocolFee; // Maker selling

        _updateUserAssets(l, quote.provider, premiumMaker, size, quote.isBuy);
    }

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
    ///         NOTE: This function can be called post or prior to expiration.
    function _annihilate(address owner, uint256 size) internal {
        _ensureNonZeroSize(size);

        PoolStorage.Layout storage l = PoolStorage.layout();

        _burn(owner, PoolStorage.SHORT, size);
        _burn(owner, PoolStorage.LONG, size);
        IERC20(l.getPoolToken()).transfer(
            owner,
            Position.contractsToCollateral(size, l.strike, l.isCallPool)
        );
    }

    /// @notice Transfer an LP position to another owner.
    ///         NOTE: This function can be called post or prior to expiration.
    /// @param srcP The position key
    /// @param newOwner The new owner of the transferred liquidity
    /// @param newOperator The new operator of the transferred liquidity
    function _transferPosition(
        Position.Key memory srcP,
        address newOwner,
        address newOperator
    ) internal {
        // ToDo : Add this logic into the ERC1155 transfer function
        if (srcP.owner == newOwner && srcP.operator == newOperator)
            revert Pool__InvalidTransfer();

        PoolStorage.Layout storage l = PoolStorage.layout();
        srcP.strike = l.strike;
        srcP.isCall = l.isCallPool;

        Position.Key memory dstP = srcP;
        dstP.owner = newOwner;
        dstP.operator = newOwner;

        bytes32 srcKey = srcP.keyHash();

        uint256 srcTokenId = PoolStorage.formatTokenId(
            srcP.operator,
            srcP.lower,
            srcP.upper,
            srcP.orderType
        );

        uint256 dstTokenId = srcP.operator == newOperator
            ? srcTokenId
            : PoolStorage.formatTokenId(
                newOperator,
                srcP.lower,
                srcP.upper,
                srcP.orderType
            );

        Position.Data storage dstData = l.positions[dstP.keyHash()];

        uint256 srcSize = _balanceOf(srcP.owner, srcTokenId);

        if (_balanceOf(newOwner, dstTokenId) > 0) {
            Position.Data storage srcData = l.positions[srcKey];

            // Call function to update claimable fees, but do not claim them
            _updateClaimableFees(l, srcP, srcData);
            // Update claimable fees to reset the fee range rate
            _updateClaimableFees(l, dstP, dstData);

            dstData.claimableFees += srcData.claimableFees;
            srcData.claimableFees = 0;

            delete l.positions[srcKey];
        } else {
            Position.Data memory srcData = l.positions[srcKey];
            delete l.positions[srcKey];
            l.positions[dstP.keyHash()] = srcData;
        }

        if (srcTokenId == dstTokenId) {
            _safeTransfer(
                address(this),
                srcP.owner,
                newOwner,
                srcTokenId,
                srcSize,
                ""
            );
        } else {
            _burn(srcP.owner, srcTokenId, srcSize);
            _mint(srcP.owner, dstTokenId, srcSize, "");
        }
    }

    function _calculateExerciseValue(
        PoolStorage.Layout storage l,
        uint256 size
    ) internal view returns (uint256) {
        _ensureNonZeroSize(size);
        _ensureExpired(l);

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

    /// @notice Exercises all long options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function _exercise(address holder) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 size = _balanceOf(holder, PoolStorage.LONG);
        uint256 exerciseValue = _calculateExerciseValue(l, size);

        // Not need to check for size > 0 as _calculateExerciseValue would revert if size == 0
        _burn(holder, PoolStorage.LONG, size);

        if (exerciseValue > 0) {
            IERC20(l.getPoolToken()).transfer(holder, exerciseValue);
        }

        return exerciseValue;
    }

    /// @notice Settles all short options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function _settle(address holder) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 size = _balanceOf(holder, PoolStorage.SHORT);

        uint256 exerciseValue = _calculateExerciseValue(l, size);
        uint256 collateralValue = _calculateCollateralValue(
            l,
            size,
            exerciseValue
        );

        // Burn short and transfer collateral to operator
        // Not need to check for size > 0 as _calculateExerciseValue would revert if size == 0
        _burn(holder, PoolStorage.SHORT, size);
        if (collateralValue > 0) {
            IERC20(l.getPoolToken()).transfer(holder, collateralValue);
        }

        return collateralValue;
    }

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    function _settlePosition(Position.Key memory p) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureNotExpired(l);

        p.strike = l.strike;
        p.isCall = l.isCallPool;

        Position.Data storage pData = l.positions[p.keyHash()];

        Tick.Data memory lowerTick = _getTick(p.lower);
        Tick.Data memory upperTick = _getTick(p.upper);

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        uint256 size = _balanceOf(p.owner, tokenId);

        {
            // Update claimable fees
            uint256 feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );

            _updateClaimableFees(pData, feeRate, p.liquidityPerTick(size));
        }

        // using the market price here is okay as the market price cannot be
        // changed through trades / deposits / withdrawals post-maturity.
        // changes to the market price are halted. thus, the market price
        // determines the amount of ask.
        // obviously, if the market was still liquid, the market price at
        // maturity should be close to the intrinsic value.
        uint256 price = l.marketPrice;
        uint256 payoff = _calculateExerciseValue(l, WAD);

        uint256 collateral = p.collateral(size, price);
        collateral += p.long(size, price).mulWad(payoff);
        collateral += p.short(size, price).mulWad(
            (l.isCallPool ? WAD : l.strike) - payoff
        );
        collateral += pData.claimableFees;

        _burn(p.owner, tokenId, size);

        pData.claimableFees = 0;
        pData.lastFeeRate = 0;

        if (collateral > 0) {
            IERC20(l.getPoolToken()).transfer(p.operator, collateral);
        }

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

    /// @notice Gets the nearest tick that is less than or equal to `price`.=
    function _getNearestTickBelow(
        uint256 price
    ) internal view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 left = l.currentTick;

        while (left != 0 && left > price) {
            left = l.tickIndex.prev(left);
        }

        uint256 next = l.tickIndex.next(left);
        while (left != 0 && next <= price) {
            left = next;
            next = l.tickIndex.next(left);
        }

        if (left == 0) revert Pool__TickNotFound();

        return left;
    }

    /// @notice Get a tick, reverts if tick is not found
    function _getTick(uint256 price) internal view returns (Tick.Data memory) {
        (Tick.Data memory tick, bool tickFound) = _tryGetTick(price);
        if (!tickFound) revert Pool__TickNotFound();

        return tick;
    }

    /// @notice Try to get tick, does not revert if tick is not found
    function _tryGetTick(
        uint256 price
    ) internal view returns (Tick.Data memory tick, bool tickFound) {
        _verifyTickWidth(price);

        if (price < Pricing.MIN_TICK_PRICE || price > Pricing.MAX_TICK_PRICE)
            revert Pool__TickOutOfRange();

        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.contains(price)) return (l.ticks[price], true);

        return (Tick.Data(0, 0), false);
    }

    /// @notice Creates a Tick for a given price, or returns the existing tick.
    /// @param price The price of the Tick
    /// @param priceBelow The price of the nearest Tick below
    /// @return tick The Tick for a given price
    function _getOrCreateTick(
        uint256 price,
        uint256 priceBelow
    ) internal returns (Tick.Data memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        (Tick.Data memory tick, bool tickFound) = _tryGetTick(price);

        if (tickFound) return tick;

        if (
            !l.tickIndex.contains(priceBelow) ||
            l.tickIndex.next(priceBelow) <= price
        ) revert Pool__InvalidBelowPrice();

        tick = Tick.Data(0, price <= l.marketPrice ? l.globalFeeRate : 0);

        l.tickIndex.insertAfter(priceBelow, price);
        l.ticks[price] = tick;

        return tick;
    }

    function _removeTickIfNotActive(uint256 price) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (!l.tickIndex.contains(price)) return;

        Tick.Data storage tick = l.ticks[price];

        if (
            price > Pricing.MIN_TICK_PRICE &&
            price < Pricing.MAX_TICK_PRICE &&
            tick.delta == 0
        ) {
            if (price == l.currentTick) {
                uint256 newCurrentTick = l.tickIndex.prev(price);

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
            while (l.tickIndex.next(l.currentTick) < marketPrice) {
                _cross(true);
            }
        } else {
            _removeTickIfNotActive(lower);
            _removeTickIfNotActive(upper);
        }
    }

    function _updateGlobalFeeRate(
        PoolStorage.Layout storage l,
        uint256 amount
    ) internal {
        if (l.liquidityRate == 0) return;
        l.globalFeeRate += amount.divWad(l.liquidityRate);
    }

    function _cross(bool isBuy) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (isBuy) {
            uint256 right = l.tickIndex.next(l.currentTick);
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

        if (!isBuy) {
            if (l.currentTick <= Pricing.MIN_TICK_PRICE)
                revert Pool__TickOutOfRange();
            l.currentTick = l.tickIndex.prev(l.currentTick);
        }
    }

    /// @notice Calculates the growth and exposure change between the lower
    ///    and upper Ticks of a Position.
    ///
    ///                     l         ▼         u
    ///    ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
    ///    => (global - external(l) - external(u))
    ///
    ///                ▼    l                   u
    ///    ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
    ///    => (global - (global - external(l)) - external(u))
    ///
    ///                     l                   u    ▼
    ///    ----|----|-------|xxxxxxxxxxxxxxxxxxx|--------|---------
    ///    => (global - external(l) - (global - external(u)))
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

    function _ensureNonZeroSize(uint256 size) internal pure {
        if (size == 0) revert Pool__ZeroSize();
    }

    function _ensureExpired(PoolStorage.Layout storage l) internal view {
        if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();
    }

    function _ensureNotExpired(PoolStorage.Layout storage l) internal view {
        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();
    }
}
