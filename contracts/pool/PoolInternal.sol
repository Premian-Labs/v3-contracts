// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IWETH} from "@solidstate/contracts/interfaces/IWETH.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ECDSA} from "@solidstate/contracts/cryptography/ECDSA.sol";

import {EIP712} from "../libraries/EIP712.sol";
import {Position} from "../libraries/Position.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {Tick} from "../libraries/Tick.sol";
import {WadMath} from "../libraries/WadMath.sol";

import {IPoolInternal} from "./IPoolInternal.sol";
import {IExchangeHelper} from "../IExchangeHelper.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is IPoolInternal, IPoolEvents, ERC1155EnumerableInternal {
    using SafeERC20 for IERC20;
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using Position for Position.OrderType;
    using Pricing for Pricing.Args;
    using WadMath for uint256;
    using Tick for Tick.Data;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Math for int256;
    using UintUtils for uint256;
    using ECDSA for bytes32;

    address internal immutable EXCHANGE_HELPER;
    address internal immutable WRAPPED_NATIVE_TOKEN;

    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    uint256 private constant WAD = 1e18;

    // ToDo : Define final values
    uint256 private constant PROTOCOL_FEE_PERCENTAGE = 5e3; // 50%
    uint256 private constant PREMIUM_FEE_PERCENTAGE = 1e2; // 1%
    uint256 private constant COLLATERAL_FEE_PERCENTAGE = 1e2; // 1%

    bytes32 private constant FILL_QUOTE_TYPE_HASH =
        keccak256("fillQuote(uint256 size,TradeQuote memory quote)");

    constructor(address exchangeHelper, address wrappedNativeToken) {
        EXCHANGE_HELPER = exchangeHelper;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
    }

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

        emit ClaimFees(
            p.owner,
            PoolStorage.formatTokenId(
                p.operator,
                p.lower,
                p.upper,
                p.orderType
            ),
            claimedFees,
            pData.lastFeeRate
        );
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    /// @param collateralCredit Collateral amount already credited before the _deposit function call. In case of a `swapAndDeposit` this would be the amount resulting from the swap
    function _deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage,
        uint256 collateralCredit
    ) internal {
        _deposit(
            p,
            belowLower,
            belowUpper,
            size,
            maxSlippage,
            collateralCredit,
            p.orderType.isLong() // We default to isBid = true if orderType is long and isBid = false if orderType is short, so that default behavior in case of stranded market price is to deposit collateral
        );
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    /// @param collateralCredit Collateral amount already credited before the _deposit function call. In case of a `swapAndDeposit` this would be the amount resulting from the swap
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)

    function _deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage,
        uint256 collateralCredit,
        bool isBidIfStrandedMarketPrice
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // Set the market price correctly in case it's stranded
        if (_isMarketPriceStranded(l, p, isBidIfStrandedMarketPrice)) {
            l.marketPrice = _getStrandedMarketPriceUpdate(
                p,
                isBidIfStrandedMarketPrice
            );
        }

        _ensureBelowMaxSlippage(l, maxSlippage);
        _ensureNonZeroSize(size);
        _ensureNotExpired(l);

        p.strike = l.strike;
        p.isCall = l.isCallPool;

        _ensureValidRange(p.lower, p.upper);
        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        Position.Delta memory delta = p.calculatePositionUpdate(
            _balanceOf(p.owner, tokenId),
            size.toInt256(),
            l.marketPrice
        );

        uint256 collateral = delta.collateral.toUint256();
        uint256 longs = delta.longs.toUint256();
        uint256 shorts = delta.shorts.toUint256();

        _transferTokens(
            l,
            p.operator,
            address(this),
            collateral,
            collateralCredit,
            longs,
            shorts
        );

        Position.Data storage pData = l.positions[p.keyHash()];

        uint256 liquidityPerTick;
        uint256 feeRate;
        {
            // If ticks dont exist they are created and inserted into the linked list
            Tick.Data memory lowerTick = _getOrCreateTick(p.lower, belowLower);
            Tick.Data memory upperTick = _getOrCreateTick(p.upper, belowUpper);

            feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );
        }

        uint256 initialSize = _balanceOf(p.owner, tokenId);

        if (initialSize > 0) {
            liquidityPerTick = p.liquidityPerTick(initialSize);

            _updateClaimableFees(pData, feeRate, liquidityPerTick);
        } else {
            pData.lastFeeRate = feeRate;
        }

        _mint(p.owner, tokenId, size, "");

        // Adjust tick deltas
        _updateTicks(
            p.lower,
            p.upper,
            l.marketPrice,
            p.liquidityPerTick(_balanceOf(p.owner, tokenId)) - liquidityPerTick,
            initialSize == 0,
            false
        );

        emit Deposit(
            p.owner,
            tokenId,
            collateral,
            longs,
            shorts,
            pData.lastFeeRate,
            pData.claimableFees,
            l.marketPrice,
            l.liquidityRate,
            l.currentTick
        );
    }

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    /// @param p The position key
    /// @param size The position size to withdraw
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    function _withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 maxSlippage
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureExpired(l);

        _ensureBelowMaxSlippage(l, maxSlippage);
        _ensureValidRange(p.lower, p.upper);
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
        bool isFullWithdrawal = initialSize == size;

        uint256 collateralToTransfer;
        if (isFullWithdrawal) {
            uint256 feesClaimed = pData.claimableFees;
            // Claim all fees and remove the position completely
            collateralToTransfer += feesClaimed;

            pData.claimableFees = 0;
            pData.lastFeeRate = 0;

            emit ClaimFees(p.owner, tokenId, feesClaimed, 0);
        }

        Position.Delta memory delta = p.calculatePositionUpdate(
            initialSize,
            -size.toInt256(),
            l.marketPrice
        );

        uint256 collateral = Math.abs(delta.collateral);
        uint256 longs = Math.abs(delta.longs);
        uint256 shorts = Math.abs(delta.shorts);

        collateralToTransfer += collateral;

        _burn(p.owner, tokenId, size);

        _transferTokens(
            l,
            address(this),
            p.operator,
            collateralToTransfer,
            0,
            longs,
            shorts
        );

        // Adjust tick deltas (reverse of deposit)
        uint256 liquidityDelta = p.liquidityPerTick(
            _balanceOf(p.owner, tokenId)
        ) - liquidityPerTick;

        _updateTicks(
            p.lower,
            p.upper,
            l.marketPrice,
            liquidityDelta,
            false,
            isFullWithdrawal
        );

        emit Withdrawal(
            p.owner,
            tokenId,
            collateral,
            longs,
            shorts,
            pData.lastFeeRate,
            pData.claimableFees,
            l.marketPrice,
            l.liquidityRate,
            l.currentTick
        );

        // ToDo : Add return values ?
    }

    /// @notice Handle transfer of collateral / longs / shorts on deposit or withdrawal
    function _transferTokens(
        PoolStorage.Layout storage l,
        address from,
        address to,
        uint256 collateral,
        uint256 collateralCredit,
        uint256 longs,
        uint256 shorts
    ) internal {
        // Safeguard, should never happen
        if (longs > 0 && shorts > 0)
            revert Pool__PositionCantHoldLongAndShort();

        address poolToken = l.getPoolToken();
        if (collateral > collateralCredit) {
            IERC20(poolToken).transferFrom(
                from,
                to,
                collateral - collateralCredit
            );
        } else if (collateralCredit > collateral) {
            // If there was too much collateral credit, we refund the excess
            IERC20(poolToken).transferFrom(
                to,
                from,
                collateralCredit - collateral
            );
        }

        if (longs + shorts > 0) {
            _safeTransfer(
                address(this),
                from,
                to,
                longs > 0 ? PoolStorage.LONG : PoolStorage.SHORT,
                longs > 0 ? longs : shorts,
                ""
            );
        }
    }

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    /// @param user The account doing the trade
    /// @param size The number of contracts being traded
    /// @param isBuy Whether the taker is buying or selling
    /// @param creditAmount Amount already credited before the _trade function call. In case of a `swapAndTrade` this would be the amount resulting from the swap
    /// @param transferCollateralToUser Whether to transfer collateral to user or not if collateral value is positive. Should be false if that collateral is used for a swap.
    /// @return totalPremium The premium paid or received by the taker for the trade
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function _trade(
        address user,
        uint256 size,
        bool isBuy,
        uint256 creditAmount,
        bool transferCollateralToUser
    ) internal returns (uint256 totalPremium, Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(size);
        _ensureNotExpired(l);

        Pricing.Args memory pricing = _getPricing(l, isBuy);

        uint256 totalTakerFees;
        uint256 totalProtocolFees;
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
                totalTakerFees += takerFee;
                totalProtocolFees += protocolFee;

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

        delta = _updateUserAssets(
            l,
            user,
            totalPremium,
            creditAmount,
            size,
            isBuy,
            transferCollateralToUser
        );

        emit Trade(
            user,
            size,
            delta.collateral,
            delta.longs,
            delta.shorts,
            isBuy ? totalPremium - totalTakerFees : totalPremium,
            totalTakerFees,
            totalProtocolFees,
            l.marketPrice,
            l.liquidityRate,
            l.currentTick,
            isBuy
        );
    }

    function _getPricing(
        PoolStorage.Layout storage l,
        bool isBuy
    ) internal view returns (Pricing.Args memory) {
        uint256 currentTick = l.currentTick;

        return
            Pricing.Args(
                l.liquidityRate,
                l.marketPrice,
                currentTick,
                l.tickIndex.next(currentTick),
                isBuy
            );
    }

    /// @notice Compute the change in short / long option contracts of an agent in order to
    ///         transfer the contracts and execute a trade.=
    function _getTradeDelta(
        address user,
        uint256 size,
        bool isBuy
    ) internal view returns (Delta memory delta) {
        uint256 longs = _balanceOf(user, PoolStorage.LONG);
        uint256 shorts = _balanceOf(user, PoolStorage.SHORT);

        if (isBuy) {
            delta.shorts = -int256(Math.min(shorts, size));
            delta.longs = int256(size) + delta.shorts;
        } else {
            delta.longs = -int256(Math.min(longs, size));
            delta.shorts = int256(size) + delta.longs;
        }
    }

    /// @notice Execute a trade by transferring the net change in short and long option
    ///         contracts and collateral to / from an agent.
    function _updateUserAssets(
        PoolStorage.Layout storage l,
        address user,
        uint256 totalPremium,
        uint256 creditAmount,
        uint256 size,
        bool isBuy,
        bool transferCollateralToUser
    ) internal returns (Delta memory delta) {
        delta = _getTradeDelta(user, size, isBuy);

        if (
            (delta.longs == 0 && delta.shorts == 0) ||
            (delta.longs > 0 && delta.shorts > 0) ||
            (delta.longs < 0 && delta.shorts < 0)
        ) revert Pool__InvalidAssetUpdate();

        bool _isBuy = delta.longs > 0 || delta.shorts < 0;

        uint256 deltaShortAbs = Math.abs(delta.shorts);
        uint256 shortCollateral = Position.contractsToCollateral(
            deltaShortAbs,
            l.strike,
            l.isCallPool
        );

        if (delta.shorts < 0) {
            delta.collateral = _isBuy
                ? int256(shortCollateral) - int256(totalPremium)
                : int256(totalPremium);
        } else {
            delta.collateral = _isBuy
                ? -int256(totalPremium)
                : int256(totalPremium) - int256(shortCollateral);
        }

        // We create a new `_deltaCollateral` variable instead of adding `creditAmount` to `delta.collateral`,
        // as we will return `delta`, and want `delta.collateral` to reflect the absolute collateral change resulting from this update
        int256 _deltaCollateral = delta.collateral;
        if (creditAmount > 0) {
            _deltaCollateral += creditAmount.toInt256();
        }

        // Transfer collateral
        if (_deltaCollateral < 0) {
            IERC20(l.getPoolToken()).transferFrom(
                user,
                address(this),
                uint256(-_deltaCollateral)
            );
        } else if (_deltaCollateral > 0 && transferCollateralToUser) {
            IERC20(l.getPoolToken()).transfer(user, uint256(_deltaCollateral));
        }

        // ToDo : See with research to fix this (Currently we wouldnt have at all time same supply for SHORT and LONG, as they arent minted for the pool)
        // Transfer long
        if (delta.longs < 0) {
            _safeTransfer(
                address(this),
                user,
                address(this),
                PoolStorage.LONG,
                uint256(-delta.longs),
                ""
            );
        } else if (delta.longs > 0) {
            _mint(user, PoolStorage.LONG, uint256(delta.longs), "");
        }

        // Transfer short
        if (delta.shorts < 0) {
            _safeTransfer(
                address(this),
                user,
                address(this),
                PoolStorage.SHORT,
                uint256(-delta.shorts),
                ""
            );
        } else if (delta.shorts > 0) {
            _mint(user, PoolStorage.SHORT, uint256(delta.shorts), "");
        }
    }

    /// @notice Functionality to support the RFQ / OTC system.
    ///         An LP can create a quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    function _fillQuote(
        address user,
        TradeQuote memory quote,
        uint256 size,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        if (size > quote.size) revert Pool__AboveQuoteSize();

        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureQuoteIsValid(l, user, quote, v, r, s);

        // Increment nonce so that quote cannot be replayed
        l.quoteNonce[user] += 1;

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

        Delta memory deltaTaker = _updateUserAssets(
            l,
            user,
            premiumTaker,
            0,
            size,
            !quote.isBuy,
            true
        );

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

        Delta memory deltaMaker = _updateUserAssets(
            l,
            quote.provider,
            premiumMaker,
            0,
            size,
            quote.isBuy,
            true
        );

        emit FillQuote(
            user,
            quote.provider,
            size,
            deltaMaker.collateral,
            deltaMaker.longs,
            deltaMaker.shorts,
            deltaTaker.collateral,
            deltaTaker.longs,
            deltaTaker.shorts,
            premium,
            takerFee,
            protocolFee,
            !quote.isBuy
        );
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

        emit Annihilate(owner, size, 0);
    }

    /// @notice Transfer an LP position to another owner.
    ///         NOTE: This function can be called post or prior to expiration.
    /// @param srcP The position key
    /// @param newOwner The new owner of the transferred liquidity
    /// @param newOperator The new operator of the transferred liquidity
    function _transferPosition(
        Position.Key memory srcP,
        address newOwner,
        address newOperator,
        uint256 size
    ) internal {
        // ToDo : Add this logic into the ERC1155 transfer function
        if (srcP.owner == newOwner && srcP.operator == newOperator)
            revert Pool__InvalidTransfer();

        if (size == 0) revert Pool__ZeroSize();

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

        uint256 srcSize = _balanceOf(srcP.owner, srcTokenId);
        if (size > srcSize) revert Pool__NotEnoughTokens();

        uint256 proportionTransferred = size.divWad(srcSize);

        Position.Data storage dstData = l.positions[dstP.keyHash()];
        Position.Data storage srcData = l.positions[srcKey];

        // Call function to update claimable fees, but do not claim them
        _updateClaimableFees(l, srcP, srcData);

        if (_balanceOf(newOwner, dstTokenId) > 0) {
            // Update claimable fees to reset the fee range rate
            _updateClaimableFees(l, dstP, dstData);
        } else {
            dstData.lastFeeRate = srcData.lastFeeRate;
        }

        uint256 feesTransferred = (proportionTransferred).mulWad(
            srcData.claimableFees
        );
        dstData.claimableFees += feesTransferred;
        srcData.claimableFees -= feesTransferred;

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

        if (size == srcSize) delete l.positions[srcKey];

        emit TransferPosition(srcP.owner, newOwner, srcTokenId, dstTokenId);
    }

    function _calculateExerciseValue(
        PoolStorage.Layout storage l,
        uint256 size
    ) internal returns (uint256) {
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

        emit Exercise(holder, size, exerciseValue, l.spot, 0);

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

        emit Settle(holder, size, exerciseValue, l.spot, 0);

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
        uint256 claimableFees = pData.claimableFees;

        uint256 collateral = p.collateral(size, price);
        collateral += p.long(size, price).mulWad(payoff);
        collateral += p.short(size, price).mulWad(
            (l.isCallPool ? WAD : l.strike) - payoff
        );
        collateral += claimableFees;

        _burn(p.owner, tokenId, size);

        pData.claimableFees = 0;
        pData.lastFeeRate = 0;

        if (collateral > 0) {
            IERC20(l.getPoolToken()).transfer(p.operator, collateral);
        }

        emit SettlePosition(
            p.owner,
            tokenId,
            size,
            collateral - claimableFees,
            payoff,
            claimableFees,
            l.spot,
            0
        );

        return collateral;
    }

    /// @dev pull token from user, send to exchangeHelper and trigger a trade from exchangeHelper
    /// @param s swap arguments
    /// @return amountCredited amount of tokenOut we got from the trade.
    /// @return tokenInRefunded amount of tokenIn left and refunded to refundAddress
    function _swap(
        IPoolInternal.SwapArgs memory s
    ) internal returns (uint256 amountCredited, uint256 tokenInRefunded) {
        if (msg.value > 0) {
            if (s.tokenIn != WRAPPED_NATIVE_TOKEN)
                revert Pool__InvalidSwapTokenIn();
            IWETH(WRAPPED_NATIVE_TOKEN).deposit{value: msg.value}();
            IWETH(WRAPPED_NATIVE_TOKEN).transfer(EXCHANGE_HELPER, msg.value);
        }
        if (s.amountInMax > 0) {
            IERC20(s.tokenIn).safeTransferFrom(
                msg.sender,
                EXCHANGE_HELPER,
                s.amountInMax
            );
        }

        (amountCredited, tokenInRefunded) = IExchangeHelper(EXCHANGE_HELPER)
            .swapWithToken(
                s.tokenIn,
                s.tokenOut,
                s.amountInMax + msg.value,
                s.callee,
                s.allowanceTarget,
                s.data,
                s.refundAddress
            );
        if (amountCredited < s.amountOutMin) revert Pool__NotEnoughSwapOutput();
    }

    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////

    ////////////////
    // TickSystem //
    ////////////////
    // ToDo : Reorganize those functions ?

    function _getNearestTicksBelow(
        uint256 lower,
        uint256 upper
    )
        internal
        view
        returns (uint256 nearestBelowLower, uint256 nearestBelowUpper)
    {
        if (lower >= upper) revert Position__LowerGreaterOrEqualUpper();

        nearestBelowLower = _getNearestTickBelow(lower);
        nearestBelowUpper = _getNearestTickBelow(upper);

        // If no tick between `lower` and `upper`, then the nearest tick below `upper`, will be `lower`
        if (nearestBelowUpper == nearestBelowLower) {
            nearestBelowUpper = lower;
        }
    }

    /// @notice Gets the nearest tick that is less than or equal to `price`.
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

        return (Tick.Data(0, 0, 0), false);
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

        tick = Tick.Data(0, price <= l.marketPrice ? l.globalFeeRate : 0, 0);

        l.tickIndex.insertAfter(priceBelow, price);
        l.ticks[price] = tick;

        return tick;
    }

    /// @notice Removes a tick if it does not mark the beginning or the end of a range order.
    function _removeTickIfNotActive(uint256 price) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (!l.tickIndex.contains(price)) return;

        Tick.Data storage tick = l.ticks[price];

        if (
            price > Pricing.MIN_TICK_PRICE &&
            price < Pricing.MAX_TICK_PRICE &&
            tick.counter == 0 // Can only remove an active tick if no active range order marks a starting / ending tick on this tick.
        ) {
            if (tick.delta != 0) revert Pool__TickDeltaNotZero();

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

    function _updateTicks(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice,
        uint256 delta,
        bool isNewDeposit,
        bool isFullWithdrawal
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        Tick.Data storage lowerTick = l.ticks[lower];
        Tick.Data storage upperTick = l.ticks[upper];

        if (isNewDeposit) {
            lowerTick.counter += 1;
            upperTick.counter += 1;
        }

        if (isFullWithdrawal) {
            lowerTick.counter -= 1;
            upperTick.counter -= 1;
        }

        // Update the deltas, i.e. the net change in per tick liquidity, of the
        // referenced lower and upper tick, dependent on the current tick.
        //
        // Three cases need to be covered.
        //
        // Case 1: current tick is above the upper tick. Upper has not been
        // crossed, thus, upon a crossing, liquidity has to be injected at the
        // upper tick and withdrawn at the lower. The bar below the range shows the
        // possible current ticks that cover case 1.
        //
        //     0   lower                upper       1
        //     |    [---------------------]         |
        //                                [---------]
        //                                  current
        //
        // Case 2: current tick is below is lower. Lower has not benn crossed yet,
        // thus, upon a crossing, liquidity has to be injected at the lower tick
        // and withdrawn at the upper.
        //
        //     0        lower                 upper 1
        //     |          [---------------------]   |
        //     [---------)
        //           current
        //
        // Case 3: current tick is greater or equal to lower and below upper. Thus,
        // liquidity has already entered. Therefore, if the price crosses the
        // lower, it needs to be withdrawn. Furthermore, if it crosses the above
        // tick it also needs to be withdrawn. Note that since the current tick lies
        // within the lower and upper range the liquidity has to be adjusted by the
        // delta.
        //
        //     0        lower                 upper 1
        //     |          [---------------------]   |
        //                [---------------------)
        //                         current

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

        // After deposit / full withdrawal the current tick needs be reconciled. We
        // need cover two cases.
        //
        // Case 1. Deposit. Depositing liquidity in case the market price is
        // stranded shifts the market price to the upper tick in case of a bid-side
        // order or to the lower tick in case of an ask-side order.
        //
        // Ask-side order:
        //      current
        //     0   v                               1
        //     |   [-bid-]               [-ask-]   |
        //               ^
        //           market price
        //                 new current
        //                    v
        //                    [-new-ask-]
        //                    ^
        //             new market price
        //
        // Bid-side order:
        //      current
        //     0   v                               1
        //     |   [-bid-]               [-ask-]   |
        //               ^
        //           market price
        //                 new current
        //                    v
        //                    [new-bid]
        //                            ^
        //                     new market price
        //
        // Case 2. Full withdrawal of [R2] where the lower tick of [R2] is the
        // current tick causes the lower and upper tick of [R2] to be removed and
        // thus shifts the current tick to the lower of [R1]. Note that the market
        // price does not change. However, around the market price zero liquidity
        // is provided. Therefore, a buy / sell trade will result in the market
        // price snapping to the upper tick of [R1] or the lower tick of [R3] and a
        // crossing of the relevant tick.
        //
        //               current
        //     0            v                      1
        //     |   [R1]     [R2]    [R3]           |
        //                   ^
        //              market price
        //     new current
        //         v
        //     |   [R1]             [R3]           |
        //                   ^
        //              market price
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

    /// @notice Given a new range order that is supposed to be deposited, a market
    ///         price is considered to be stranded if within the range order' range
    ///         there's no liquidity provided, and the lower and upper ticks are between
    ///         the current tick and the tick right of the current tick.
    ///
    ///         Example: Assume R1 and R2 are existing orders. The area below the two
    ///           range orders marked with the x's marks the area in which a range order
    ///           may be deposited. An ask-side order deposited within that range would
    ///           change the market price to the lower tick (indicated by the upward
    ///           arrow). A bid-side order would change the market price to the upper tick of
    ///           that range order (again indicated by an arrow below the range order).
    ///
    ///           |---R1---|                          |---R2---|
    ///                    |xxxxxxxxxxxxxxxxxxxxxxxxxx|
    ///                                 |---ask---|
    ///                                 ^
    ///                     |---bid---|
    ///                               ^
    function _isMarketPriceStranded(
        PoolStorage.Layout storage l,
        Position.Key memory p,
        bool isBid
    ) internal view returns (bool) {
        uint256 right = l.tickIndex.next(l.currentTick);

        bool isStranded = l.liquidityRate == 0 &&
            p.lower >= l.currentTick &&
            p.upper <= right;

        if (isStranded) return true;
        if (right == Pricing.MAX_TICK_PRICE) return isStranded;

        uint256 rightRight = l.tickIndex.next(right);

        return (l.ticks[right].delta < 0 &&
            l.liquidityRate == uint256(-l.ticks[right].delta) &&
            isBid &&
            l.marketPrice == right &&
            p.lower >= right &&
            p.upper <= rightRight);
    }

    /// @notice In case the market price is stranded the market price needs to be
    ///         set to the upper (lower) tick of the bid (ask) order. See docstring of
    ///         isMarketPriceStranded.
    function _getStrandedMarketPriceUpdate(
        Position.Key memory p,
        bool isBid
    ) internal pure returns (uint256) {
        return isBid ? p.upper : p.lower;
    }

    function _verifyTickWidth(uint256 price) internal pure {
        if (price % Pricing.MIN_TICK_DISTANCE != 0)
            revert Pool__TickWidthInvalid();
    }

    function _ensureValidRange(uint256 lower, uint256 upper) internal pure {
        if (
            lower == 0 ||
            upper == 0 ||
            lower >= upper ||
            upper > Pricing.MAX_TICK_PRICE
        ) revert Pool__InvalidRange();
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

    function _ensureBelowMaxSlippage(
        PoolStorage.Layout storage l,
        uint256 maxSlippage
    ) internal view {
        uint256 lowerBound = (WAD - maxSlippage).mulWad(l.marketPrice);
        uint256 upperBound = (WAD + maxSlippage).mulWad(l.marketPrice);

        if (lowerBound > l.marketPrice || l.marketPrice > upperBound)
            revert Pool__AboveMaxSlippage();
    }

    function _ensureQuoteIsValid(
        PoolStorage.Layout storage l,
        address user,
        TradeQuote memory quote,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        if (block.timestamp > quote.deadline) revert Pool__QuoteExpired();

        if (
            Pricing.MIN_TICK_PRICE > quote.price ||
            quote.price > Pricing.MAX_TICK_PRICE
        ) revert Pool__OutOfBoundsPrice();

        if (user != quote.taker) revert Pool__InvalidQuoteTaker();
        if (l.quoteNonce[user] != quote.nonce) revert Pool__InvalidQuoteNonce();

        bytes32 structHash = keccak256(abi.encode(FILL_QUOTE_TYPE_HASH, quote));

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                EIP712.calculateDomainSeparator(
                    keccak256("Premia"),
                    keccak256("1")
                ),
                structHash
            )
        );

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != quote.provider) revert Pool__InvalidQuoteSignature();
    }
}
