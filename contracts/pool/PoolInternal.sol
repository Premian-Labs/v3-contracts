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
import {UD60x18} from "../libraries/prbMath/UD60x18.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {Tick} from "../libraries/Tick.sol";

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
    using Tick for Tick.Data;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Math for int256;
    using UintUtils for uint256;
    using ECDSA for bytes32;
    using UD60x18 for uint256;

    address internal immutable EXCHANGE_HELPER;
    address internal immutable WRAPPED_NATIVE_TOKEN;

    uint256 private constant ONE = 1e18;

    // ToDo : Add getter for fee values
    // ToDo : Define final values
    uint256 private constant PROTOCOL_FEE_PERCENTAGE = 5e17; // 50%
    uint256 private constant PREMIUM_FEE_PERCENTAGE = 1e16; // 1%
    uint256 private constant COLLATERAL_FEE_PERCENTAGE = 1e16; // 1%

    bytes32 private constant FILL_QUOTE_TYPE_HASH =
        keccak256(
            "FillQuote(address provider,address taker,uint256 price,uint256 size,bool isBuy,uint256 nonce,uint256 deadline)"
        );

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
        uint256 premiumFee = premium.mul(PREMIUM_FEE_PERCENTAGE);
        // 3% of premium
        uint256 notionalFee = size.mul(COLLATERAL_FEE_PERCENTAGE);
        // 0.3% of notional
        return Math.max(premiumFee, notionalFee);
    }

    function _getTradeQuote(
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
                uint256 priceDelta = (pricing.upper - pricing.lower).mul(
                    tradeSize.div(liquidity)
                );

                nextPrice = isBuy
                    ? pricing.marketPrice + priceDelta
                    : pricing.marketPrice - priceDelta;
            }

            {
                uint256 premium = Math
                    .average(pricing.marketPrice, nextPrice)
                    .mul(tradeSize);
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
            if (maxSize >= size - (ONE / 10)) {
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
        uint256 claimableFees = (feeRate - pData.lastFeeRate).mul(
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
            DepositArgsInternal(
                belowLower,
                belowUpper,
                size,
                maxSlippage,
                collateralCredit,
                p.orderType.isLong() // We default to isBid = true if orderType is long and isBid = false if orderType is short, so that default behavior in case of stranded market price is to deposit collateral
            )
        );
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param args The deposit parameters
    function _deposit(
        Position.Key memory p,
        DepositArgsInternal memory args
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // Set the market price correctly in case it's stranded
        if (_isMarketPriceStranded(l, p, args.isBidIfStrandedMarketPrice)) {
            l.marketPrice = _getStrandedMarketPriceUpdate(
                p,
                args.isBidIfStrandedMarketPrice
            );
        }

        _ensureBelowMaxSlippage(l, args.maxSlippage);
        _ensureNonZeroSize(args.size);
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
            args.size.toInt256(),
            l.marketPrice
        );

        _transferTokens(
            l,
            p.operator,
            address(this),
            delta.collateral.toUint256(),
            args.collateralCredit,
            delta.longs.toUint256(),
            delta.shorts.toUint256()
        );

        Position.Data storage pData = l.positions[p.keyHash()];
        _depositFeeAndTicksUpdate(
            l,
            pData,
            p,
            args.belowLower,
            args.belowUpper,
            args.size,
            tokenId
        );

        emit Deposit(
            p.owner,
            tokenId,
            delta.collateral.toUint256(),
            delta.longs.toUint256(),
            delta.shorts.toUint256(),
            pData.lastFeeRate,
            pData.claimableFees,
            l.marketPrice,
            l.liquidityRate,
            l.currentTick
        );
    }

    function _depositFeeAndTicksUpdate(
        PoolStorage.Layout storage l,
        Position.Data storage pData,
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 tokenId
    ) internal {
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
        uint256 liquidityPerTick;

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
            false,
            p.orderType
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

        uint256 liquidityPerTick;

        {
            Tick.Data memory lowerTick = _getTick(p.lower);
            Tick.Data memory upperTick = _getTick(p.upper);

            // Initialize variables before position update
            liquidityPerTick = p.liquidityPerTick(initialSize);
            uint256 feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );

            // Update claimable fees
            _updateClaimableFees(pData, feeRate, liquidityPerTick);
        }

        // Check whether it's a full withdrawal before updating the position

        Position.Delta memory delta;

        {
            uint256 collateralToTransfer;
            // If full withdrawal
            if (initialSize == size) {
                uint256 feesClaimed = pData.claimableFees;
                // Claim all fees and remove the position completely
                collateralToTransfer += feesClaimed;

                pData.claimableFees = 0;
                pData.lastFeeRate = 0;

                emit ClaimFees(p.owner, tokenId, feesClaimed, 0);
            }

            delta = p.calculatePositionUpdate(
                initialSize,
                -size.toInt256(),
                l.marketPrice
            );

            collateralToTransfer += Math.abs(delta.collateral);

            _burn(p.owner, tokenId, size);

            _transferTokens(
                l,
                address(this),
                p.operator,
                collateralToTransfer,
                0,
                Math.abs(delta.longs),
                Math.abs(delta.shorts)
            );
        }

        _updateTicks(
            p.lower,
            p.upper,
            l.marketPrice,
            p.liquidityPerTick(_balanceOf(p.owner, tokenId)) - liquidityPerTick, // Adjust tick deltas (reverse of deposit)
            false,
            initialSize == size, // isFullWithdrawal,
            p.orderType
        );

        emit Withdrawal(
            p.owner,
            tokenId,
            Math.abs(delta.collateral),
            Math.abs(delta.longs),
            Math.abs(delta.shorts),
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

    struct TradeUpdate {
        uint128 totalTakerFees;
        uint128 totalProtocolFees;        
        uint128 longDelta;
        uint128 shortDelta;
    }

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    /// @param args Trade parameters
    /// @return totalPremium The premium paid or received by the taker for the trade
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function _trade(
        TradeArgsInternal memory args
    ) internal returns (uint256 totalPremium, Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(args.size);
        _ensureNotExpired(l);

        TradeUpdate memory update;

        {
            uint256 remaining = args.size;
            Pricing.Args memory pricing = _getPricing(l, args.isBuy);

            while (remaining > 0) {
                uint256 maxSize = pricing.maxTradeSize();
                uint256 tradeSize = Math.min(remaining, maxSize);
                uint256 oldMarketPrice = l.marketPrice;

                {
                    uint256 nextMarketPrice;
                    if (tradeSize != maxSize) {
                        nextMarketPrice = pricing.nextPrice(tradeSize);
                    } else {
                        nextMarketPrice = args.isBuy
                            ? pricing.upper
                            : pricing.lower;
                    }

                    uint256 premium;

                    {
                        uint256 tradeQuotePrice = Math.average(
                            l.marketPrice,
                            nextMarketPrice
                        );

                        premium = tradeQuotePrice.mul(tradeSize);
                    }
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
                    uint256 protocolFee = takerFee.mul(PROTOCOL_FEE_PERCENTAGE);

                    {
                        uint256 makerRebate = takerFee - protocolFee;
                        _updateGlobalFeeRate(l, makerRebate);
                    }

                    // is_buy: taker has to pay premium + fees
                    // ~is_buy: taker receives premium - fees
                    totalPremium += args.isBuy
                        ? uint128(premium + takerFee)
                        : uint128(premium - takerFee);
                    update.totalTakerFees += uint128(takerFee);
                    update.totalProtocolFees += uint128(protocolFee);

                    l.marketPrice = nextMarketPrice;
                    l.protocolFees += protocolFee;
                }

                uint256 dist = Math.abs(int256(l.marketPrice) - int256(oldMarketPrice));

                update.shortDelta += uint128(l.shortRate * PoolStorage.MIN_TICK_DISTANCE * dist);
                update.longDelta += uint128(l.longRate * PoolStorage.MIN_TICK_DISTANCE * dist);

                // ToDo : Deal with rounding error
                if (maxSize >= remaining - (ONE / 10)) {
                    remaining = 0;
                } else {
                    // The trade will require crossing into the next tick range
                    if (
                        args.isBuy &&
                        l.tickIndex.next(l.currentTick) >=
                        Pricing.MAX_TICK_PRICE
                    ) revert Pool__InsufficientAskLiquidity();

                    if (!args.isBuy && l.currentTick <= Pricing.MIN_TICK_PRICE)
                        revert Pool__InsufficientBidLiquidity();

                    remaining -= tradeSize;
                    _cross(args.isBuy);
                }
            }
        }

        delta = _updateUserAssets(
            l,
            args.user,
            totalPremium,
            args.creditAmount,
            args.size,
            args.isBuy,
            args.transferCollateralToUser
        );

        if (args.isBuy) {
            if (update.shortDelta > 0)
                _mint(address(this), PoolStorage.SHORT, uint256(update.shortDelta), "");

            if (update.longDelta > 0)
                _burn(address(this), PoolStorage.LONG, uint256(update.longDelta));
        } else {
            if (update.longDelta > 0)
                _mint(address(this), PoolStorage.LONG, uint256(update.longDelta), "");
            
            if (update.shortDelta > 0)
                _burn(address(this), PoolStorage.SHORT, uint256(update.shortDelta));
        }

        emit Trade(
            args.user,
            args.size,
            delta,
            args.isBuy ? totalPremium - update.totalTakerFees : totalPremium,
            update.totalTakerFees,
            update.totalProtocolFees,
            l.marketPrice,
            l.liquidityRate,
            l.currentTick,
            args.isBuy
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

        // Transfer long
        if (delta.longs < 0) {
            _burn(user, PoolStorage.LONG, uint256(-delta.longs));
        } else if (delta.longs > 0) {
            _mint(user, PoolStorage.LONG, uint256(delta.longs), "");
        }

        // Transfer short
        if (delta.shorts < 0) {
            _burn(user, PoolStorage.SHORT, uint256(-delta.shorts));
        } else if (delta.shorts > 0) {
            _mint(user, PoolStorage.SHORT, uint256(delta.shorts), "");
        }
    }

    /// @notice Functionality to support the RFQ / OTC system.
    ///         An LP can create a quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    /// @param args The fillQuote parameters
    /// @param tradeQuote The quote given by the provider
    function _fillQuote(
        FillQuoteArgsInternal memory args,
        TradeQuote memory tradeQuote
    ) internal {
        if (args.size > tradeQuote.size) revert Pool__AboveQuoteSize();

        FillQuoteVarsInternal memory vars;
        Delta memory deltaTaker;
        Delta memory deltaMaker;

        {
            PoolStorage.Layout storage l = PoolStorage.layout();

            _ensureQuoteIsValid(
                l,
                args.user,
                tradeQuote,
                args.v,
                args.r,
                args.s
            );

            // Increment nonce so that quote cannot be replayed
            l.tradeQuoteNonce[args.user] += 1;

            vars.premium = tradeQuote.price.mul(args.size);
            vars.takerFee = Position.contractsToCollateral(
                _takerFee(args.size, vars.premium),
                l.strike,
                l.isCallPool
            );

            // Denormalize premium
            vars.premium = Position.contractsToCollateral(
                vars.premium,
                l.strike,
                l.isCallPool
            );

            vars.protocolFee = vars.takerFee.mul(PROTOCOL_FEE_PERCENTAGE);
            vars.makerRebate = vars.takerFee - vars.protocolFee;
            l.protocolFees += vars.protocolFee;

            /////////////////////////
            // Process trade taker //
            /////////////////////////

            vars.premiumTaker = !tradeQuote.isBuy
                ? vars.premium // Taker Buying
                : vars.premium - vars.takerFee; // Taker selling

            deltaTaker = _updateUserAssets(
                l,
                args.user,
                vars.premiumTaker,
                0,
                args.size,
                !tradeQuote.isBuy,
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

            vars.premiumMaker = tradeQuote.isBuy
                ? vars.premium - vars.makerRebate // Maker buying
                : vars.premium - vars.protocolFee; // Maker selling

            deltaMaker = _updateUserAssets(
                l,
                tradeQuote.provider,
                vars.premiumMaker,
                0,
                args.size,
                tradeQuote.isBuy,
                true
            );
        }

        emit FillQuote(
            args.user,
            tradeQuote.provider,
            args.size,
            deltaMaker,
            deltaTaker,
            vars.premium,
            vars.takerFee,
            vars.protocolFee,
            !tradeQuote.isBuy
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

        uint256 proportionTransferred = size.div(srcSize);

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

        uint256 feesTransferred = (proportionTransferred).mul(
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

        uint256 exerciseValue = size.mul(intrinsicValue);

        if (isCall) {
            exerciseValue = exerciseValue.div(spot);
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
                : size.mul(l.strike) - exerciseValue;
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
        uint256 claimableFees = pData.claimableFees;
        uint256 payoff = _calculateExerciseValue(l, ONE);
        uint256 collateral = p.collateral(size, l.marketPrice);
        collateral += p.long(size, l.marketPrice).mul(payoff);
        collateral += p.short(size, l.marketPrice).mul(
            (l.isCallPool ? ONE : l.strike) - payoff
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

        return (Tick.Data(0, 0, 0, 0, 0), false);
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

        tick = Tick.Data(0, price <= l.marketPrice ? l.globalFeeRate : 0, 0, 0, 0);

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
        bool isFullWithdrawal,
        Position.OrderType orderType
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

            if (orderType.isLong()) {
                lowerTick.longDelta -= _delta;
                upperTick.longDelta += _delta;
            } else {
                lowerTick.shortDelta -= _delta;
                upperTick.shortDelta += _delta;
            }
        } else if (lower > l.currentTick) {
            lowerTick.delta += _delta;
            upperTick.delta -= _delta;

            if (orderType.isLong()) {
                lowerTick.longDelta += _delta;
                upperTick.longDelta -= _delta;
            } else {
                lowerTick.shortDelta += _delta;
                upperTick.shortDelta -= _delta;
            }
        } else {
            lowerTick.delta -= _delta;
            upperTick.delta -= _delta;
            l.liquidityRate += delta;
            
            if (orderType.isLong()) {
                lowerTick.longDelta -= _delta;
                upperTick.longDelta -= _delta;
                l.longRate = uint256(int256(l.longRate) + _delta);
            } else {
                lowerTick.shortDelta -= _delta;
                upperTick.shortDelta -= _delta;
                l.shortRate = uint256(int256(l.shortRate) + _delta);
            }
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
            uint256 crossings;

            while (l.tickIndex.next(l.currentTick) < marketPrice) {
                _cross(true);
                crossings++;
            }

            while (l.currentTick > marketPrice) {
                _cross(false);
                crossings++;
            }

            if (crossings > 2) revert Pool__InvalidReconciliation();
        } else {
            _removeTickIfNotActive(lower);
            _removeTickIfNotActive(upper);
        }
    }

    function _updateGlobalFeeRate(
        PoolStorage.Layout storage l,
        uint256 makerRebate
    ) internal {
        if (l.liquidityRate == 0) return;
        l.globalFeeRate += makerRebate.div(l.liquidityRate);
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
        l.longRate = uint256(int256(l.longRate) + currentTick.longDelta);
        l.shortRate = uint256(int256(l.shortRate) + currentTick.shortDelta);

        // Flip the tick
        currentTick.delta = -currentTick.delta;
        currentTick.longDelta = -currentTick.longDelta;
        currentTick.shortDelta = -currentTick.shortDelta;

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

    /// @notice Gets the lower and upper bound of the stranded market area when it
    ///         exists. In case the stranded market area does not exist it will return
    ///         s the stranded market area the maximum tick price for both the lower
    ///         and the upper, in which case the market price is not stranded given
    ///         any range order info order.
    /// @return lower Lower bound of the stranded market price area (Default : 1e18)
    /// @return upper Upper bound of the stranded market price area (Default : 1e18)
    function _getStrandedArea(
        PoolStorage.Layout storage l
    ) internal view returns (uint256 lower, uint256 upper) {
        lower = ONE;
        upper = ONE;

        uint256 current = l.currentTick;
        uint256 right = l.tickIndex.next(current);

        if (l.liquidityRate == 0) {
            // applies whenever the pool is empty or the last active order that
            // was traversed by the price was withdrawn
            // the check is independent of the current market price
            lower = current;
            upper = right;
        } else if (
            -l.ticks[right].delta > 0 &&
            l.liquidityRate == uint256(-l.ticks[right].delta) &&
            right == l.marketPrice &&
            l.tickIndex.next(right) != 0
        ) {
            // bid-bound market price check
            // liquidity_rate > 0
            //        market price
            //             v
            // |------[----]------|
            //        ^
            //     current
            lower = right;
            upper = l.tickIndex.next(right);
        } else if (
            -l.ticks[current].delta > 0 &&
            l.liquidityRate == uint256(-l.ticks[current].delta) &&
            current == l.marketPrice &&
            l.tickIndex.prev(current) != 0
        ) {
            //  ask-bound market price check
            //  liquidity_rate > 0
            //  market price
            //        v
            // |------[----]------|
            //        ^
            //     current
            lower = l.tickIndex.prev(current);
            upper = current;
        }
    }

    function _isMarketPriceStranded(
        PoolStorage.Layout storage l,
        Position.Key memory p,
        bool isBid
    ) internal view returns (bool) {
        (uint256 lower, uint256 upper) = _getStrandedArea(l);
        uint256 tick = isBid ? p.upper : p.lower;
        return lower <= tick && tick <= upper;
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
        uint256 lowerBound = (ONE - maxSlippage).mul(l.marketPrice);
        uint256 upperBound = (ONE + maxSlippage).mul(l.marketPrice);

        if (lowerBound > l.marketPrice || l.marketPrice > upperBound)
            revert Pool__AboveMaxSlippage();
    }

    function _ensureQuoteIsValid(
        PoolStorage.Layout storage l,
        address user,
        TradeQuote memory tradeQuote,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        if (block.timestamp > tradeQuote.deadline) revert Pool__QuoteExpired();

        if (
            Pricing.MIN_TICK_PRICE > tradeQuote.price ||
            tradeQuote.price > Pricing.MAX_TICK_PRICE
        ) revert Pool__OutOfBoundsPrice();

        if (user != tradeQuote.taker) revert Pool__InvalidQuoteTaker();
        if (l.tradeQuoteNonce[user] != tradeQuote.nonce)
            revert Pool__InvalidQuoteNonce();

        bytes32 structHash = keccak256(
            abi.encode(
                FILL_QUOTE_TYPE_HASH,
                tradeQuote.provider,
                tradeQuote.taker,
                tradeQuote.price,
                tradeQuote.size,
                tradeQuote.isBuy,
                tradeQuote.nonce,
                tradeQuote.deadline
            )
        );

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
        if (signer != tradeQuote.provider) revert Pool__InvalidQuoteSignature();
    }
}
