// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IWETH} from "@solidstate/contracts/interfaces/IWETH.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ECDSA} from "@solidstate/contracts/cryptography/ECDSA.sol";

import {IPoolFactory} from "../factory/IPoolFactory.sol";
import {IERC20Router} from "../router/IERC20Router.sol";

import {EIP712} from "../libraries/EIP712.sol";
import {Position} from "../libraries/Position.sol";
import {UD60x18} from "../libraries/prbMath/UD60x18.sol";
import {Pricing} from "../libraries/Pricing.sol";

import {IPoolInternal} from "./IPoolInternal.sol";
import {IExchangeHelper} from "../IExchangeHelper.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is IPoolInternal, IPoolEvents, ERC1155EnumerableInternal {
    using SafeERC20 for IERC20;
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using PoolStorage for PoolStorage.Layout;
    using PoolStorage for TradeQuote;
    using Position for Position.Key;
    using Position for Position.OrderType;
    using Pricing for Pricing.Args;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Math for int256;
    using UintUtils for uint256;
    using ECDSA for bytes32;
    using UD60x18 for uint256;

    address internal immutable FACTORY;
    address internal immutable ROUTER;
    address internal immutable EXCHANGE_HELPER;
    address internal immutable WRAPPED_NATIVE_TOKEN;
    address internal immutable FEE_RECEIVER;

    uint256 private constant ONE = 1e18;

    // ToDo : Define final values
    uint256 private constant PROTOCOL_FEE_PERCENTAGE = 5e17; // 50%
    uint256 private constant PREMIUM_FEE_PERCENTAGE = 3e16; // 3%
    uint256 private constant COLLATERAL_FEE_PERCENTAGE = 3e15; // 0.3%

    bytes32 private constant FILL_QUOTE_TYPE_HASH =
        keccak256(
            "FillQuote(address provider,address taker,uint256 price,uint256 size,bool isBuy,uint256 deadline,uint256 salt)"
        );

    constructor(
        address factory,
        address router,
        address exchangeHelper,
        address wrappedNativeToken,
        address feeReceiver
    ) {
        FACTORY = factory;
        ROUTER = router;
        EXCHANGE_HELPER = exchangeHelper;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        FEE_RECEIVER = feeReceiver;
    }

    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param size The size of a trade (number of contracts)
    /// @param premium The total cost of option(s) for a purchase
    /// @param isPremiumNormalized Whether the premium given is already normalized by strike or not (Ex: For a strike of 1500, and a premium of 750, the normalized premium would be 0.5)
    /// @return The taker fee for an option trade denormalized
    function _takerFee(
        PoolStorage.Layout storage l,
        uint256 size,
        uint256 premium,
        bool isPremiumNormalized
    ) internal view returns (uint256) {
        uint256 strike = l.strike;
        bool isCallPool = l.isCallPool;

        if (!isPremiumNormalized) {
            // Normalize premium
            premium = Position.collateralToContracts(
                premium,
                strike,
                isCallPool
            );
        }

        uint256 premiumFee = premium.mul(PREMIUM_FEE_PERCENTAGE);
        uint256 notionalFee = size.mul(COLLATERAL_FEE_PERCENTAGE);

        return
            Position.contractsToCollateral(
                Math.max(premiumFee, notionalFee),
                strike,
                isCallPool
            );
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

            if (tradeSize > 0) {
                uint256 premium = Math
                    .average(pricing.marketPrice, nextPrice)
                    .mul(tradeSize);
                uint256 takerFee = _takerFee(l, size, premium, true);

                // Denormalize premium
                premium = Position.contractsToCollateral(
                    premium,
                    l.strike,
                    l.isCallPool
                );

                totalPremium += isBuy ? premium + takerFee : premium - takerFee;
            }

            pricing.marketPrice = nextPrice;

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
                    : l.tickIndex.prev(pricing.lower);
                pricing.upper = l.tickIndex.next(pricing.lower);

                if (pricing.upper == 0) revert Pool__InsufficientLiquidity();

                // Compute new liquidity
                liquidity = pricing.liquidity();
                maxSize = pricing.maxTradeSize();
            }
        }

        return totalPremium;
    }

    // @notice Returns amount of claimable fees from pending update of claimable fees for the position. This does not include pData.claimableFees
    function _pendingClaimableFees(
        PoolStorage.Layout storage l,
        Position.Key memory p,
        Position.Data storage pData
    ) internal view returns (uint256 claimableFees, uint256 feeRate) {
        Tick memory lowerTick = _getTick(p.lower);
        Tick memory upperTick = _getTick(p.upper);

        feeRate = _rangeFeeRate(
            l,
            p.lower,
            p.upper,
            lowerTick.externalFeeRate,
            upperTick.externalFeeRate
        );

        claimableFees = _calculateClaimableFees(
            feeRate,
            pData.lastFeeRate,
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

    function _calculateClaimableFees(
        uint256 feeRate,
        uint256 lastFeeRate,
        uint256 liquidityPerTick
    ) internal pure returns (uint256) {
        return (feeRate - lastFeeRate).mul(liquidityPerTick);
    }

    /// @notice Updates the amount of fees an LP can claim for a position (without claiming).
    function _updateClaimableFees(
        Position.Data storage pData,
        uint256 feeRate,
        uint256 liquidityPerTick
    ) internal {
        pData.claimableFees += _calculateClaimableFees(
            feeRate,
            pData.lastFeeRate,
            liquidityPerTick
        );

        // Reset the initial range rate of the position
        pData.lastFeeRate = feeRate;
    }

    function _updateClaimableFees(
        PoolStorage.Layout storage l,
        Position.Key memory p,
        Position.Data storage pData
    ) internal {
        (uint256 claimableFees, uint256 feeRate) = _pendingClaimableFees(
            l,
            p,
            pData
        );

        pData.claimableFees += claimableFees;
        pData.lastFeeRate = feeRate;
    }

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    function _claim(
        Position.Key memory p
    ) internal returns (uint256 claimedFees) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.protocolFees > 0) _claimProtocolFees();

        Position.Data storage pData = l.positions[p.keyHash()];
        _updateClaimableFees(l, p, pData);
        claimedFees = pData.claimableFees;

        pData.claimableFees = 0;
        IERC20(l.getPoolToken()).safeTransfer(p.operator, claimedFees);

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

    function _claimProtocolFees() internal returns (uint256 claimedFees) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        claimedFees = l.protocolFees;

        if (claimedFees == 0) return 0;

        l.protocolFees = 0;
        IERC20(l.getPoolToken()).safeTransfer(FEE_RECEIVER, claimedFees);
        emit ClaimProtocolFees(FEE_RECEIVER, claimedFees);
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param args The deposit parameters
    function _deposit(
        Position.Key memory p,
        DepositArgsInternal memory args
    ) internal {
        _deposit(
            p,
            args,
            p.orderType.isLong() // We default to isBid = true if orderType is long and isBid = false if orderType is short, so that default behavior in case of stranded market price is to deposit collateral
        );
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param args The deposit parameters
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)
    function _deposit(
        Position.Key memory p,
        DepositArgsInternal memory args,
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

        _ensureBelowDepositWithdrawMaxSlippage(
            l.marketPrice,
            args.minMarketPrice,
            args.maxMarketPrice
        );
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
            args.refundAddress,
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
            Tick memory lowerTick = _getOrCreateTick(p.lower, belowLower);
            Tick memory upperTick = _getOrCreateTick(p.upper, belowUpper);

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

        int256 tickDelta = p
            .liquidityPerTick(_balanceOf(p.owner, tokenId))
            .toInt256() - liquidityPerTick.toInt256();

        // Adjust tick deltas
        _updateTicks(
            p.lower,
            p.upper,
            l.marketPrice,
            tickDelta,
            initialSize == 0,
            false,
            p.orderType
        );
    }

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param p The position key
    /// @param size The position size to withdraw
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert)
    function _withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 minMarketPrice,
        uint256 maxMarketPrice
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureNotExpired(l);

        _ensureBelowDepositWithdrawMaxSlippage(
            l.marketPrice,
            minMarketPrice,
            maxMarketPrice
        );
        _ensureNonZeroSize(size);
        _ensureValidRange(p.lower, p.upper);
        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        p.strike = l.strike;
        p.isCall = l.isCallPool;

        Position.Data storage pData = l.positions[p.keyHash()];

        WithdrawVarsInternal memory vars;

        vars.tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        vars.initialSize = _balanceOf(p.owner, vars.tokenId);

        if (vars.initialSize == 0) revert Pool__PositionDoesNotExist();

        vars.isFullWithdrawal = vars.initialSize == size;

        {
            Tick memory lowerTick = _getTick(p.lower);
            Tick memory upperTick = _getTick(p.upper);

            // Initialize variables before position update
            vars.liquidityPerTick = p.liquidityPerTick(vars.initialSize);
            uint256 feeRate = _rangeFeeRate(
                l,
                p.lower,
                p.upper,
                lowerTick.externalFeeRate,
                upperTick.externalFeeRate
            );

            // Update claimable fees
            _updateClaimableFees(pData, feeRate, vars.liquidityPerTick);
        }

        // Check whether it's a full withdrawal before updating the position

        Position.Delta memory delta;

        {
            uint256 collateralToTransfer;
            if (vars.isFullWithdrawal) {
                uint256 feesClaimed = pData.claimableFees;
                // Claim all fees and remove the position completely
                collateralToTransfer += feesClaimed;

                pData.claimableFees = 0;
                pData.lastFeeRate = 0;

                emit ClaimFees(p.owner, vars.tokenId, feesClaimed, 0);
            }

            delta = p.calculatePositionUpdate(
                vars.initialSize,
                -size.toInt256(),
                l.marketPrice
            );

            collateralToTransfer += Math.abs(delta.collateral);

            _burn(p.owner, vars.tokenId, size);

            _transferTokens(
                l,
                address(this),
                p.operator,
                collateralToTransfer,
                0,
                address(0),
                Math.abs(delta.longs),
                Math.abs(delta.shorts)
            );
        }

        {
            int256 tickDelta = p
                .liquidityPerTick(_balanceOf(p.owner, vars.tokenId))
                .toInt256() - vars.liquidityPerTick.toInt256();

            _updateTicks(
                p.lower,
                p.upper,
                l.marketPrice,
                tickDelta, // Adjust tick deltas (reverse of deposit)
                false,
                vars.isFullWithdrawal,
                p.orderType
            );
        }

        emit Withdrawal(
            p.owner,
            vars.tokenId,
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
        address refundAddress,
        uint256 longs,
        uint256 shorts
    ) internal {
        // Safeguard, should never happen
        if (longs > 0 && shorts > 0)
            revert Pool__PositionCantHoldLongAndShort();

        address poolToken = l.getPoolToken();
        if (collateral > collateralCredit) {
            if (from == address(this)) {
                IERC20(poolToken).safeTransfer(
                    to,
                    collateral - collateralCredit
                );
            } else {
                IERC20Router(ROUTER).safeTransferFrom(
                    poolToken,
                    from,
                    to,
                    collateral - collateralCredit
                );
            }
        } else if (collateralCredit > collateral) {
            // If there was too much collateral credit, we refund the excess
            IERC20(poolToken).safeTransfer(
                refundAddress,
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

    function _writeFrom(
        address underwriter,
        address longReceiver,
        uint256 size
    ) internal {
        if (
            msg.sender != underwriter &&
            ERC1155BaseStorage.layout().operatorApprovals[underwriter][
                msg.sender
            ] ==
            false
        ) revert Pool__NotAuthorized();

        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(size);
        _ensureNotExpired(l);

        uint256 collateral = Position.contractsToCollateral(
            size,
            l.strike,
            l.isCallPool
        );
        uint256 protocolFee = Position.contractsToCollateral(
            _takerFee(l, size, 0, true),
            l.strike,
            l.isCallPool
        );

        IERC20Router(ROUTER).safeTransferFrom(
            l.getPoolToken(),
            underwriter,
            address(this),
            collateral + protocolFee
        );

        l.protocolFees += protocolFee;

        _mint(underwriter, PoolStorage.SHORT, size, "");
        _mint(longReceiver, PoolStorage.LONG, size, "");

        emit WriteFrom(
            underwriter,
            longReceiver,
            size,
            collateral,
            protocolFee
        );
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

        TradeVarsInternal memory vars;

        {
            uint256 remaining = args.size;

            while (remaining > 0) {
                Pricing.Args memory pricing = _getPricing(l, args.isBuy);
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
                    uint256 takerFee = _takerFee(l, tradeSize, premium, true);

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
                        ? premium + takerFee
                        : premium - takerFee;
                    vars.totalTakerFees += takerFee;
                    vars.totalProtocolFees += protocolFee;

                    l.marketPrice = nextMarketPrice;
                    l.protocolFees += protocolFee;
                }

                uint256 dist = Math.abs(
                    l.marketPrice.toInt256() - oldMarketPrice.toInt256()
                );

                vars.shortDelta += l.shortRate.mul(dist).div(
                    PoolStorage.MIN_TICK_DISTANCE
                );
                vars.longDelta += l.longRate.mul(dist).div(
                    PoolStorage.MIN_TICK_DISTANCE
                );

                if (maxSize >= remaining) {
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

        _ensureBelowTradeMaxSlippage(
            totalPremium,
            args.premiumLimit,
            args.isBuy
        );

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
            if (vars.shortDelta > 0)
                _mint(address(this), PoolStorage.SHORT, vars.shortDelta, "");

            if (vars.longDelta > 0)
                _burn(address(this), PoolStorage.LONG, vars.longDelta);
        } else {
            if (vars.longDelta > 0)
                _mint(address(this), PoolStorage.LONG, vars.longDelta, "");

            if (vars.shortDelta > 0)
                _burn(address(this), PoolStorage.SHORT, vars.shortDelta);
        }

        emit Trade(
            args.user,
            args.size,
            delta,
            args.isBuy ? totalPremium - vars.totalTakerFees : totalPremium,
            vars.totalTakerFees,
            vars.totalProtocolFees,
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
            delta.shorts = -Math.min(shorts, size).toInt256();
            delta.longs = size.toInt256() + delta.shorts;
        } else {
            delta.longs = -Math.min(longs, size).toInt256();
            delta.shorts = size.toInt256() + delta.longs;
        }
    }

    function _calculateAssetsUpdate(
        PoolStorage.Layout storage l,
        address user,
        uint256 totalPremium,
        uint256 size,
        bool isBuy
    ) internal view returns (Delta memory delta) {
        delta = _getTradeDelta(user, size, isBuy);

        bool _isBuy = delta.longs > 0 || delta.shorts < 0;

        uint256 shortCollateral = Position.contractsToCollateral(
            Math.abs(delta.shorts),
            l.strike,
            l.isCallPool
        );

        if (_isBuy) {
            delta.collateral =
                -Math.min(shortCollateral, 0).toInt256() -
                totalPremium.toInt256();
        } else {
            delta.collateral =
                totalPremium.toInt256() -
                Math.max(shortCollateral, 0).toInt256();
        }

        return delta;
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
        delta = _calculateAssetsUpdate(l, user, totalPremium, size, isBuy);

        if (
            (delta.longs == 0 && delta.shorts == 0) ||
            (delta.longs > 0 && delta.shorts > 0) ||
            (delta.longs < 0 && delta.shorts < 0)
        ) revert Pool__InvalidAssetUpdate();

        // We create a new `_deltaCollateral` variable instead of adding `creditAmount` to `delta.collateral`,
        // as we will return `delta`, and want `delta.collateral` to reflect the absolute collateral change resulting from this update
        int256 _deltaCollateral = delta.collateral;
        if (creditAmount > 0) {
            _deltaCollateral += creditAmount.toInt256();
        }

        // Transfer collateral
        if (_deltaCollateral < 0) {
            IERC20Router(ROUTER).safeTransferFrom(
                l.getPoolToken(),
                user,
                address(this),
                uint256(-_deltaCollateral)
            );
        } else if (_deltaCollateral > 0 && transferCollateralToUser) {
            IERC20(l.getPoolToken()).safeTransfer(
                user,
                uint256(_deltaCollateral)
            );
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

    function _calculateQuotePremiumAndFee(
        PoolStorage.Layout storage l,
        uint256 size,
        uint256 price,
        bool isBuy
    ) internal view returns (PremiumAndFeeInternal memory r) {
        r.premium = price.mul(size);
        r.protocolFee = Position.contractsToCollateral(
            _takerFee(l, size, r.premium, true),
            l.strike,
            l.isCallPool
        );

        // Denormalize premium
        r.premium = Position.contractsToCollateral(
            r.premium,
            l.strike,
            l.isCallPool
        );

        r.premiumMaker = isBuy
            ? r.premium // Maker buying
            : r.premium - r.protocolFee; // Maker selling

        r.premiumTaker = !isBuy
            ? r.premium // Taker Buying
            : r.premium - r.protocolFee; // Taker selling

        return r;
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

        PoolStorage.Layout storage l = PoolStorage.layout();
        bytes32 tradeQuoteHash = _tradeQuoteHash(tradeQuote);
        _ensureQuoteIsValid(l, args, tradeQuote, tradeQuoteHash);

        PremiumAndFeeInternal
            memory premiumAndFee = _calculateQuotePremiumAndFee(
                l,
                args.size,
                tradeQuote.price,
                tradeQuote.isBuy
            );

        // Update amount filled for this quote
        l.tradeQuoteAmountFilled[tradeQuote.provider][tradeQuoteHash] += args
            .size;

        // Update protocol fees
        l.protocolFees += premiumAndFee.protocolFee;

        // Process trade taker
        Delta memory deltaTaker = _updateUserAssets(
            l,
            args.user,
            premiumAndFee.premiumTaker,
            0,
            args.size,
            !tradeQuote.isBuy,
            true
        );

        // Process trade maker
        Delta memory deltaMaker = _updateUserAssets(
            l,
            tradeQuote.provider,
            premiumAndFee.premiumMaker,
            0,
            args.size,
            tradeQuote.isBuy,
            true
        );

        emit FillQuote(
            tradeQuoteHash,
            args.user,
            tradeQuote.provider,
            args.size,
            deltaMaker,
            deltaTaker,
            premiumAndFee.premium,
            premiumAndFee.protocolFee,
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
        IERC20(l.getPoolToken()).safeTransfer(
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

        Position.Key memory dstP = Position.Key({
            owner: newOwner,
            operator: newOperator,
            lower: srcP.lower,
            upper: srcP.upper,
            orderType: srcP.orderType,
            strike: srcP.strike,
            isCall: srcP.isCall
        });

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
                size,
                ""
            );
        } else {
            _burn(srcP.owner, srcTokenId, size);
            _mint(newOwner, dstTokenId, size, "");
        }

        if (size == srcSize) delete l.positions[srcKey];

        emit TransferPosition(srcP.owner, newOwner, srcTokenId, dstTokenId);
    }

    function _calculateExerciseValue(
        PoolStorage.Layout storage l,
        uint256 size
    ) internal returns (uint256) {
        if (size == 0) return 0;

        uint256 spot = l.fetchAndCacheQuote();
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
        _ensureExpired(l);

        if (l.protocolFees > 0) _claimProtocolFees();

        uint256 size = _balanceOf(holder, PoolStorage.LONG);
        if (size == 0) return 0;

        uint256 exerciseValue = _calculateExerciseValue(l, size);

        _removeFromFactory(l);

        _burn(holder, PoolStorage.LONG, size);

        if (exerciseValue > 0) {
            IERC20(l.getPoolToken()).safeTransfer(holder, exerciseValue);
        }

        emit Exercise(holder, size, exerciseValue, l.spot, 0);

        return exerciseValue;
    }

    /// @notice Settles all short options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function _settle(address holder) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureExpired(l);

        if (l.protocolFees > 0) _claimProtocolFees();

        uint256 size = _balanceOf(holder, PoolStorage.SHORT);
        if (size == 0) return 0;

        uint256 exerciseValue = _calculateExerciseValue(l, size);
        uint256 collateralValue = _calculateCollateralValue(
            l,
            size,
            exerciseValue
        );

        _removeFromFactory(l);

        // Burn short and transfer collateral to operator
        _burn(holder, PoolStorage.SHORT, size);
        if (collateralValue > 0) {
            IERC20(l.getPoolToken()).safeTransfer(holder, collateralValue);
        }

        emit Settle(holder, size, exerciseValue, l.spot, 0);

        return collateralValue;
    }

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    function _settlePosition(Position.Key memory p) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureExpired(l);
        _removeFromFactory(l);

        if (l.protocolFees > 0) _claimProtocolFees();

        p.strike = l.strike;
        p.isCall = l.isCallPool;

        Position.Data storage pData = l.positions[p.keyHash()];

        Tick memory lowerTick = _getTick(p.lower);
        Tick memory upperTick = _getTick(p.upper);

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        uint256 size = _balanceOf(p.owner, tokenId);
        if (size == 0) return 0;

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

        uint256 claimableFees;
        uint256 payoff;
        uint256 collateral;

        {
            uint256 longs = p.long(size, l.marketPrice);
            uint256 shorts = p.short(size, l.marketPrice);

            claimableFees = pData.claimableFees;
            payoff = _calculateExerciseValue(l, ONE);
            collateral = p.collateral(size, l.marketPrice);
            collateral += longs.mul(payoff);
            collateral += shorts.mul((l.isCallPool ? ONE : l.strike) - payoff);

            collateral += claimableFees;

            _burn(p.owner, tokenId, size);

            if (longs > 0) {
                _burn(address(this), PoolStorage.LONG, longs);
            }

            if (shorts > 0) {
                _burn(address(this), PoolStorage.SHORT, shorts);
            }
        }

        pData.claimableFees = 0;
        pData.lastFeeRate = 0;

        if (collateral > 0) {
            IERC20(l.getPoolToken()).safeTransfer(p.operator, collateral);
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
            IERC20Router(ROUTER).safeTransferFrom(
                s.tokenIn,
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
    function _getTick(uint256 price) internal view returns (Tick memory) {
        (Tick memory tick, bool tickFound) = _tryGetTick(price);
        if (!tickFound) revert Pool__TickNotFound();

        return tick;
    }

    /// @notice Try to get tick, does not revert if tick is not found
    function _tryGetTick(
        uint256 price
    ) internal view returns (Tick memory tick, bool tickFound) {
        _verifyTickWidth(price);

        if (price < Pricing.MIN_TICK_PRICE || price > Pricing.MAX_TICK_PRICE)
            revert Pool__TickOutOfRange();

        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.contains(price)) return (l.ticks[price], true);

        return (Tick(0, 0, 0, 0, 0), false);
    }

    /// @notice Creates a Tick for a given price, or returns the existing tick.
    /// @param price The price of the Tick
    /// @param priceBelow The price of the nearest Tick below
    /// @return tick The Tick for a given price
    function _getOrCreateTick(
        uint256 price,
        uint256 priceBelow
    ) internal returns (Tick memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        (Tick memory tick, bool tickFound) = _tryGetTick(price);

        if (tickFound) return tick;

        if (
            !l.tickIndex.contains(priceBelow) ||
            l.tickIndex.next(priceBelow) <= price
        ) revert Pool__InvalidBelowPrice();

        tick = Tick(0, price <= l.marketPrice ? l.globalFeeRate : 0, 0, 0, 0);

        l.tickIndex.insertAfter(priceBelow, price);
        l.ticks[price] = tick;

        return tick;
    }

    /// @notice Removes a tick if it does not mark the beginning or the end of a range order.
    function _removeTickIfNotActive(uint256 price) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (!l.tickIndex.contains(price)) return;

        Tick storage tick = l.ticks[price];

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
        int256 delta,
        bool isNewDeposit,
        bool isFullWithdrawal,
        Position.OrderType orderType
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        Tick storage lowerTick = l.ticks[lower];
        Tick storage upperTick = l.ticks[upper];

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

        if (upper <= l.currentTick) {
            lowerTick.delta -= delta;
            upperTick.delta += delta;

            if (orderType.isLong()) {
                lowerTick.longDelta -= delta;
                upperTick.longDelta += delta;
            } else {
                lowerTick.shortDelta -= delta;
                upperTick.shortDelta += delta;
            }
        } else if (lower > l.currentTick) {
            lowerTick.delta += delta;
            upperTick.delta -= delta;

            if (orderType.isLong()) {
                lowerTick.longDelta += delta;
                upperTick.longDelta -= delta;
            } else {
                lowerTick.shortDelta += delta;
                upperTick.shortDelta -= delta;
            }
        } else {
            lowerTick.delta -= delta;
            upperTick.delta -= delta;
            l.liquidityRate = l.liquidityRate.add(delta);

            if (orderType.isLong()) {
                lowerTick.longDelta -= delta;
                upperTick.longDelta -= delta;
                l.longRate = l.longRate.add(delta);
            } else {
                lowerTick.shortDelta -= delta;
                upperTick.shortDelta -= delta;
                l.shortRate = l.shortRate.add(delta);
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

        Tick storage currentTick = l.ticks[l.currentTick];

        l.liquidityRate = l.liquidityRate.add(currentTick.delta);
        l.longRate = l.longRate.add(currentTick.longDelta);
        l.shortRate = l.shortRate.add(currentTick.shortDelta);

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

    function _removeFromFactory(PoolStorage.Layout storage l) internal {
        if (l.hasRemoved) return;

        l.hasRemoved = true;

        IPoolFactory(FACTORY).removeDiscount(
            IPoolFactory.PoolKey(
                l.base,
                l.quote,
                l.oracleAdapter,
                l.strike,
                l.maturity,
                l.isCallPool
            )
        );
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

    function _tradeQuoteHash(
        IPoolInternal.TradeQuote memory tradeQuote
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                FILL_QUOTE_TYPE_HASH,
                tradeQuote.provider,
                tradeQuote.taker,
                tradeQuote.price,
                tradeQuote.size,
                tradeQuote.isBuy,
                tradeQuote.deadline,
                tradeQuote.salt
            )
        );

        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    EIP712.calculateDomainSeparator(
                        keccak256("Premia"),
                        keccak256("1")
                    ),
                    structHash
                )
            );
    }

    function _ensureValidRange(uint256 lower, uint256 upper) internal pure {
        if (
            lower == 0 ||
            upper == 0 ||
            lower >= upper ||
            lower < Pricing.MIN_TICK_PRICE ||
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

    function _ensureBelowTradeMaxSlippage(
        uint256 totalPremium,
        uint256 premiumLimit,
        bool isBuy
    ) internal pure {
        if (isBuy && totalPremium > premiumLimit)
            revert Pool__AboveMaxSlippage();
        if (!isBuy && totalPremium < premiumLimit)
            revert Pool__AboveMaxSlippage();
    }

    function _ensureBelowDepositWithdrawMaxSlippage(
        uint256 marketPrice,
        uint256 minMarketPrice,
        uint256 maxMarketPrice
    ) internal pure {
        if (marketPrice > maxMarketPrice || marketPrice < minMarketPrice)
            revert Pool__AboveMaxSlippage();
    }

    function _areQuoteAndBalanceValid(
        PoolStorage.Layout storage l,
        FillQuoteArgsInternal memory args,
        TradeQuote memory tradeQuote,
        bytes32 tradeQuoteHash
    ) internal view returns (bool isValid, InvalidQuoteError error) {
        (isValid, error) = _isQuoteValid(l, args, tradeQuote, tradeQuoteHash);
        if (!isValid) {
            return (isValid, error);
        }
        return _isQuoteBalanceValid(l, args, tradeQuote);
    }

    function _ensureQuoteIsValid(
        PoolStorage.Layout storage l,
        FillQuoteArgsInternal memory args,
        TradeQuote memory tradeQuote,
        bytes32 tradeQuoteHash
    ) internal view {
        (bool isValid, InvalidQuoteError error) = _isQuoteValid(
            l,
            args,
            tradeQuote,
            tradeQuoteHash
        );

        if (isValid) return;

        if (error == InvalidQuoteError.QuoteExpired)
            revert Pool__QuoteExpired();
        if (error == InvalidQuoteError.QuoteCancelled)
            revert Pool__QuoteCancelled();
        if (error == InvalidQuoteError.QuoteOverfilled)
            revert Pool__QuoteOverfilled();
        if (error == InvalidQuoteError.OutOfBoundsPrice)
            revert Pool__OutOfBoundsPrice();
        if (error == InvalidQuoteError.InvalidQuoteTaker)
            revert Pool__InvalidQuoteTaker();
        if (error == InvalidQuoteError.InvalidQuoteSignature)
            revert Pool__InvalidQuoteSignature();

        revert Pool__ErrorNotHandled();
    }

    function _isQuoteValid(
        PoolStorage.Layout storage l,
        FillQuoteArgsInternal memory args,
        TradeQuote memory tradeQuote,
        bytes32 tradeQuoteHash
    ) internal view returns (bool, InvalidQuoteError) {
        if (block.timestamp > tradeQuote.deadline)
            return (false, InvalidQuoteError.QuoteExpired);

        uint256 filledAmount = l.tradeQuoteAmountFilled[tradeQuote.provider][
            tradeQuoteHash
        ];

        if (filledAmount == type(uint256).max)
            return (false, InvalidQuoteError.QuoteCancelled);

        if (filledAmount + args.size > tradeQuote.size)
            return (false, InvalidQuoteError.QuoteOverfilled);

        if (
            Pricing.MIN_TICK_PRICE > tradeQuote.price ||
            tradeQuote.price > Pricing.MAX_TICK_PRICE
        ) return (false, InvalidQuoteError.OutOfBoundsPrice);

        if (tradeQuote.taker != address(0) && args.user != tradeQuote.taker)
            return (false, InvalidQuoteError.InvalidQuoteTaker);

        address signer = ECDSA.recover(
            tradeQuoteHash,
            args.signature.v,
            args.signature.r,
            args.signature.s
        );
        if (signer != tradeQuote.provider)
            return (false, InvalidQuoteError.InvalidQuoteSignature);

        return (true, InvalidQuoteError.None);
    }

    function _isQuoteBalanceValid(
        PoolStorage.Layout storage l,
        FillQuoteArgsInternal memory args,
        TradeQuote memory tradeQuote
    ) internal view returns (bool, InvalidQuoteError) {
        PremiumAndFeeInternal
            memory premiumAndFee = _calculateQuotePremiumAndFee(
                l,
                args.size,
                tradeQuote.price,
                tradeQuote.isBuy
            );

        Delta memory delta = _calculateAssetsUpdate(
            l,
            args.user,
            premiumAndFee.premium,
            args.size,
            tradeQuote.isBuy
        );

        if (
            (delta.longs == 0 && delta.shorts == 0) ||
            (delta.longs > 0 && delta.shorts > 0) ||
            (delta.longs < 0 && delta.shorts < 0)
        ) return (false, InvalidQuoteError.InvalidAssetUpdate);

        if (delta.collateral < 0) {
            IERC20 token = IERC20(l.getPoolToken());
            if (
                token.allowance(args.user, ROUTER) < uint256(-delta.collateral)
            ) {
                return (
                    false,
                    InvalidQuoteError.InsufficientCollateralAllowance
                );
            }

            if (token.balanceOf(args.user) < uint256(-delta.collateral)) {
                return (false, InvalidQuoteError.InsufficientCollateralBalance);
            }
        }

        if (
            delta.longs < 0 &&
            _balanceOf(args.user, PoolStorage.LONG) < uint256(-delta.longs)
        ) {
            return (false, InvalidQuoteError.InsufficientLongBalance);
        }

        if (
            delta.shorts < 0 &&
            _balanceOf(args.user, PoolStorage.SHORT) < uint256(-delta.shorts)
        ) {
            return (false, InvalidQuoteError.InsufficientShortBalance);
        }

        return (true, InvalidQuoteError.None);
    }

    function _ensureOperator(address operator) internal view {
        if (operator != msg.sender) revert Pool__NotAuthorized();
    }
}
