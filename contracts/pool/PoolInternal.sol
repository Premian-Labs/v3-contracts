// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Math} from "@solidstate/contracts/utils/Math.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IWETH} from "@solidstate/contracts/interfaces/IWETH.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ECDSA} from "@solidstate/contracts/cryptography/ECDSA.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {IPoolFactory} from "../factory/IPoolFactory.sol";
import {IERC20Router} from "../router/IERC20Router.sol";

import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../libraries/DoublyLinkedListUD60x18.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";
import {iZERO, ZERO, ONE} from "../libraries/Constants.sol";

import {IPoolInternal} from "./IPoolInternal.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is IPoolInternal, IPoolEvents, ERC1155EnumerableInternal {
    using SafeERC20 for IERC20;
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using PoolStorage for IERC20;
    using PoolStorage for IERC20Router;
    using PoolStorage for PoolStorage.Layout;
    using PoolStorage for QuoteRFQ;
    using Position for Position.KeyInternal;
    using Position for Position.OrderType;
    using Pricing for Pricing.Args;
    using SafeCast for uint256;
    using Math for int256;
    using ECDSA for bytes32;
    using PRBMathExtra for UD60x18;
    using PRBMathExtra for SD59x18;

    address internal immutable FACTORY;
    address internal immutable ROUTER;
    address internal immutable WRAPPED_NATIVE_TOKEN;
    address internal immutable FEE_RECEIVER;

    // ToDo : Define final values
    UD60x18 internal constant PROTOCOL_FEE_PERCENTAGE = UD60x18.wrap(0.5e18); // 50%
    UD60x18 internal constant PREMIUM_FEE_PERCENTAGE = UD60x18.wrap(0.03e18); // 3%
    UD60x18 internal constant COLLATERAL_FEE_PERCENTAGE =
        UD60x18.wrap(0.003e18); // 0.3%

    // Number of seconds required to pass before a deposit can be withdrawn (To prevent flash loans and JIT)
    uint256 internal constant WITHDRAWAL_DELAY = 60;

    bytes32 internal constant FILL_QUOTE_RFQ_TYPE_HASH =
        keccak256(
            "FillQuoteRFQ(address provider,address taker,uint256 price,uint256 size,bool isBuy,uint256 deadline,uint256 salt)"
        );

    constructor(
        address factory,
        address router,
        address wrappedNativeToken,
        address feeReceiver
    ) {
        FACTORY = factory;
        ROUTER = router;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        FEE_RECEIVER = feeReceiver;
    }

    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param size The size of a trade (number of contracts) (18 decimals)
    /// @param premium The total cost of option(s) for a purchase (18 decimals)
    /// @param isPremiumNormalized Whether the premium given is already normalized by strike or not (Ex: For a strike of 1500, and a premium of 750, the normalized premium would be 0.5)
    /// @return The taker fee for an option trade denormalized (18 decimals)
    function _takerFee(
        PoolStorage.Layout storage l,
        UD60x18 size,
        UD60x18 premium,
        bool isPremiumNormalized
    ) internal view returns (UD60x18) {
        UD60x18 strike = l.strike;
        bool isCallPool = l.isCallPool;

        if (!isPremiumNormalized) {
            // Normalize premium
            premium = Position.collateralToContracts(
                premium,
                strike,
                isCallPool
            );
        }

        UD60x18 premiumFee = premium * PREMIUM_FEE_PERCENTAGE;
        UD60x18 notionalFee = size * COLLATERAL_FEE_PERCENTAGE;

        return
            Position.contractsToCollateral(
                PRBMathExtra.max(premiumFee, notionalFee),
                strike,
                isCallPool
            );
    }

    /// @notice Gives a quote for a trade
    /// @param size The number of contracts being traded (18 decimals)
    /// @param isBuy Whether the taker is buying or selling
    /// @return totalNetPremium The premium which has to be paid to complete the trade (Net of fees) (poolToken decimals)
    /// @return totalTakerFee The taker fees to pay (Included in `premiumNet`) (poolToken decimals)
    function _getQuoteAMM(
        UD60x18 size,
        bool isBuy
    ) internal view returns (uint256 totalNetPremium, uint256 totalTakerFee) {
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

        UD60x18 liquidity = pricing.liquidity();
        UD60x18 maxSize = pricing.maxTradeSize();

        UD60x18 totalPremium;
        UD60x18 _totalTakerFee;

        while (size > ZERO) {
            UD60x18 tradeSize = PRBMathExtra.min(size, maxSize);

            UD60x18 nextPrice;
            // Compute next price
            if (liquidity == ZERO) {
                nextPrice = isBuy ? pricing.upper : pricing.lower;
            } else {
                UD60x18 priceDelta = ((pricing.upper - pricing.lower) *
                    tradeSize) / liquidity;

                nextPrice = isBuy
                    ? pricing.marketPrice + priceDelta
                    : pricing.marketPrice - priceDelta;
            }

            if (tradeSize > ZERO) {
                UD60x18 premium = pricing.marketPrice.avg(nextPrice) *
                    tradeSize;
                UD60x18 takerFee = _takerFee(l, size, premium, true);

                // Denormalize premium
                premium = Position.contractsToCollateral(
                    premium,
                    l.strike,
                    l.isCallPool
                );

                _totalTakerFee = _totalTakerFee + takerFee;
                totalPremium = totalPremium + premium;
            }

            pricing.marketPrice = nextPrice;

            if (maxSize >= size) {
                size = ZERO;
            } else {
                // Cross tick
                size = size - maxSize;

                // Adjust liquidity rate
                pricing.liquidityRate = pricing.liquidityRate.add(
                    l.ticks[isBuy ? pricing.upper : pricing.lower].delta
                );

                // Set new lower and upper bounds
                pricing.lower = isBuy
                    ? pricing.upper
                    : l.tickIndex.prev(pricing.lower);
                pricing.upper = l.tickIndex.next(pricing.lower);

                if (pricing.upper == ZERO) revert Pool__InsufficientLiquidity();

                // Compute new liquidity
                liquidity = pricing.liquidity();
                maxSize = pricing.maxTradeSize();
            }
        }

        return (
            l.toPoolTokenDecimals(
                isBuy
                    ? totalPremium + _totalTakerFee
                    : totalPremium - _totalTakerFee
            ),
            l.toPoolTokenDecimals(_totalTakerFee)
        );
    }

    // @notice Returns amount of claimable fees from pending update of claimable fees for the position. This does not include pData.claimableFees
    function _pendingClaimableFees(
        PoolStorage.Layout storage l,
        Position.KeyInternal memory p,
        Position.Data storage pData
    ) internal view returns (UD60x18 claimableFees, UD60x18 feeRate) {
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
                _balanceOfUD60x18(
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
        UD60x18 feeRate,
        UD60x18 lastFeeRate,
        UD60x18 liquidityPerTick
    ) internal pure returns (UD60x18) {
        return (feeRate - lastFeeRate) * liquidityPerTick;
    }

    /// @notice Updates the amount of fees an LP can claim for a position (without claiming).
    function _updateClaimableFees(
        Position.Data storage pData,
        UD60x18 feeRate,
        UD60x18 liquidityPerTick
    ) internal {
        pData.claimableFees =
            pData.claimableFees +
            _calculateClaimableFees(
                feeRate,
                pData.lastFeeRate,
                liquidityPerTick
            );

        // Reset the initial range rate of the position
        pData.lastFeeRate = feeRate;
    }

    function _updateClaimableFees(
        PoolStorage.Layout storage l,
        Position.KeyInternal memory p,
        Position.Data storage pData
    ) internal {
        (UD60x18 claimableFees, UD60x18 feeRate) = _pendingClaimableFees(
            l,
            p,
            pData
        );

        pData.claimableFees = pData.claimableFees + claimableFees;
        pData.lastFeeRate = feeRate;
    }

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    /// @param p The position to claim fees for
    /// @return claimedFees The amount of fees claimed (poolToken decimals)
    function _claim(
        Position.KeyInternal memory p
    ) internal returns (uint256 claimedFees) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.protocolFees > ZERO) _claimProtocolFees();

        Position.Data storage pData = l.positions[p.keyHash()];
        _updateClaimableFees(l, p, pData);
        UD60x18 _claimedFees = pData.claimableFees;

        pData.claimableFees = ZERO;
        IERC20(l.getPoolToken()).safeTransfer(p.operator, _claimedFees);

        emit ClaimFees(
            p.owner,
            PoolStorage.formatTokenId(
                p.operator,
                p.lower,
                p.upper,
                p.orderType
            ),
            _claimedFees,
            pData.lastFeeRate
        );

        return l.toPoolTokenDecimals(_claimedFees);
    }

    function _claimProtocolFees() internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 claimedFees = l.protocolFees;

        if (claimedFees == ZERO) return;

        l.protocolFees = ZERO;
        IERC20(l.getPoolToken()).safeTransfer(FEE_RECEIVER, claimedFees);
        emit ClaimProtocolFees(FEE_RECEIVER, claimedFees);
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param args The deposit parameters
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return delta The amount of collateral / longs / shorts deposited
    function _deposit(
        Position.KeyInternal memory p,
        DepositArgsInternal memory args,
        Permit2.Data memory permit
    ) internal returns (Position.Delta memory delta) {
        return
            _deposit(
                p,
                args,
                permit,
                p.orderType.isLong() // We default to isBid = true if orderType is long and isBid = false if orderType is short, so that default behavior in case of stranded market price is to deposit collateral
            );
    }

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param args The deposit parameters
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)
    /// @return delta The amount of collateral / longs / shorts deposited
    function _deposit(
        Position.KeyInternal memory p,
        DepositArgsInternal memory args,
        Permit2.Data memory permit,
        bool isBidIfStrandedMarketPrice
    ) internal returns (Position.Delta memory delta) {
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

        _ensureValidRange(p.lower, p.upper);
        _verifyTickWidth(p.lower);
        _verifyTickWidth(p.upper);

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        delta = p.calculatePositionUpdate(
            _balanceOfUD60x18(p.owner, tokenId),
            args.size.intoSD59x18(),
            l.marketPrice
        );

        _transferTokens(
            l,
            p.operator,
            address(this),
            l.toPoolTokenDecimals(delta.collateral.intoUD60x18()),
            args.collateralCredit,
            args.refundAddress,
            delta.longs.intoUD60x18(),
            delta.shorts.intoUD60x18(),
            permit
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

        pData.lastDeposit = block.timestamp;

        emit Deposit(
            p.owner,
            tokenId,
            delta.collateral.intoUD60x18(),
            delta.longs.intoUD60x18(),
            delta.shorts.intoUD60x18(),
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
        Position.KeyInternal memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        uint256 tokenId
    ) internal {
        UD60x18 feeRate;
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

        UD60x18 initialSize = _balanceOfUD60x18(p.owner, tokenId);
        UD60x18 liquidityPerTick;

        if (initialSize > ZERO) {
            liquidityPerTick = p.liquidityPerTick(initialSize);

            _updateClaimableFees(pData, feeRate, liquidityPerTick);
        } else {
            pData.lastFeeRate = feeRate;
        }

        _mint(p.owner, tokenId, size);

        SD59x18 tickDelta = p
            .liquidityPerTick(_balanceOfUD60x18(p.owner, tokenId))
            .intoSD59x18() - liquidityPerTick.intoSD59x18();

        // Adjust tick deltas
        _updateTicks(
            p.lower,
            p.upper,
            l.marketPrice,
            tickDelta,
            initialSize == ZERO,
            false,
            p.orderType
        );
    }

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param p The position key
    /// @param size The position size to withdraw (18 decimals)
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) (18 decimals)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) (18 decimals)
    /// @param transferCollateralToUser Whether to transfer collateral to user or not if collateral value is positive. Should be false if that collateral is used for a swap
    /// @return delta The amount of collateral / longs / shorts withdrawn
    function _withdraw(
        Position.KeyInternal memory p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        bool transferCollateralToUser
    ) internal returns (Position.Delta memory delta) {
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

        Position.Data storage pData = l.positions[p.keyHash()];

        _ensureWithdrawalDelayElapsed(pData);

        WithdrawVarsInternal memory vars;

        vars.tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        vars.initialSize = _balanceOfUD60x18(p.owner, vars.tokenId);

        if (vars.initialSize == ZERO)
            revert Pool__PositionDoesNotExist(p.owner, vars.tokenId);

        vars.isFullWithdrawal = vars.initialSize == size;

        {
            Tick memory lowerTick = _getTick(p.lower);
            Tick memory upperTick = _getTick(p.upper);

            // Initialize variables before position update
            vars.liquidityPerTick = p.liquidityPerTick(vars.initialSize);
            UD60x18 feeRate = _rangeFeeRate(
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

        {
            UD60x18 collateralToTransfer;
            if (vars.isFullWithdrawal) {
                UD60x18 feesClaimed = pData.claimableFees;
                // Claim all fees and remove the position completely
                collateralToTransfer = collateralToTransfer + feesClaimed;

                pData.claimableFees = ZERO;
                pData.lastFeeRate = ZERO;

                emit ClaimFees(p.owner, vars.tokenId, feesClaimed, ZERO);
            }

            delta = p.calculatePositionUpdate(
                vars.initialSize,
                -size.intoSD59x18(),
                l.marketPrice
            );

            delta.collateral = delta.collateral.abs();
            delta.longs = delta.longs.abs();
            delta.shorts = delta.shorts.abs();

            collateralToTransfer =
                collateralToTransfer +
                delta.collateral.intoUD60x18();

            _burn(p.owner, vars.tokenId, size);

            _transferTokens(
                l,
                address(this),
                p.operator,
                transferCollateralToUser
                    ? l.toPoolTokenDecimals(collateralToTransfer)
                    : 0,
                0,
                address(0),
                delta.longs.intoUD60x18(),
                delta.shorts.intoUD60x18(),
                Permit2.emptyPermit()
            );
        }

        vars.tickDelta =
            p
                .liquidityPerTick(_balanceOfUD60x18(p.owner, vars.tokenId))
                .intoSD59x18() -
            vars.liquidityPerTick.intoSD59x18();

        _updateTicks(
            p.lower,
            p.upper,
            l.marketPrice,
            vars.tickDelta, // Adjust tick deltas (reverse of deposit)
            false,
            vars.isFullWithdrawal,
            p.orderType
        );

        emit Withdrawal(
            p.owner,
            vars.tokenId,
            delta.collateral.intoUD60x18(),
            delta.longs.intoUD60x18(),
            delta.shorts.intoUD60x18(),
            pData.lastFeeRate,
            pData.claimableFees,
            l.marketPrice,
            l.liquidityRate,
            l.currentTick
        );
    }

    /// @notice Handle transfer of collateral / longs / shorts on deposit or withdrawal
    ///         WARNING : `collateral` and `collateralCredit` must be scaled to the collateral token decimals
    function _transferTokens(
        PoolStorage.Layout storage l,
        address from,
        address to,
        uint256 collateral,
        uint256 collateralCredit,
        address refundAddress,
        UD60x18 longs,
        UD60x18 shorts,
        Permit2.Data memory permit
    ) internal {
        // Safeguard, should never happen
        if (longs > ZERO && shorts > ZERO)
            revert Pool__PositionCantHoldLongAndShort(longs, shorts);

        address poolToken = l.getPoolToken();

        if (from == address(this)) {
            require(collateralCredit == 0); // Just a safety check, should never fail
            IERC20(poolToken).safeTransfer(to, collateral);
        } else if (collateral > collateralCredit) {
            _transferFromWithPermitOrRouter(
                permit,
                poolToken,
                from,
                to,
                collateral - collateralCredit
            );
        } else if (collateral < collateralCredit) {
            // If there was too much collateral credit, we refund the excess
            IERC20(poolToken).safeTransfer(
                refundAddress,
                collateralCredit - collateral
            );
        }

        if (longs + shorts > ZERO) {
            _safeTransfer(
                address(this),
                from,
                to,
                longs > ZERO ? PoolStorage.LONG : PoolStorage.SHORT,
                longs > ZERO ? longs.unwrap() : shorts.unwrap(),
                ""
            );
        }
    }

    function _writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size,
        Permit2.Data memory permit
    ) internal {
        if (
            msg.sender != underwriter &&
            ERC1155BaseStorage.layout().operatorApprovals[underwriter][
                msg.sender
            ] ==
            false
        ) revert Pool__NotAuthorized(msg.sender);

        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(size);
        _ensureNotExpired(l);

        UD60x18 collateral = Position.contractsToCollateral(
            size,
            l.strike,
            l.isCallPool
        );
        UD60x18 protocolFee = _takerFee(l, size, ZERO, true);

        _transferFromWithPermitOrRouter(
            permit,
            l.getPoolToken(),
            underwriter,
            address(this),
            collateral + protocolFee
        );

        l.protocolFees = l.protocolFees + protocolFee;

        _mint(underwriter, PoolStorage.SHORT, size);
        _mint(longReceiver, PoolStorage.LONG, size);

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
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return totalPremium The premium paid or received by the taker for the trade (poolToken decimals)
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function _trade(
        TradeArgsInternal memory args,
        Permit2.Data memory permit
    ) internal returns (uint256 totalPremium, Position.Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureNonZeroSize(args.size);
        _ensureNotExpired(l);

        TradeVarsInternal memory vars;

        {
            UD60x18 remaining = args.size;

            while (remaining > ZERO) {
                Pricing.Args memory pricing = _getPricing(l, args.isBuy);
                UD60x18 maxSize = pricing.maxTradeSize();
                UD60x18 tradeSize = PRBMathExtra.min(remaining, maxSize);
                UD60x18 oldMarketPrice = l.marketPrice;

                {
                    UD60x18 nextMarketPrice;
                    if (tradeSize != maxSize) {
                        nextMarketPrice = pricing.nextPrice(tradeSize);
                    } else {
                        nextMarketPrice = args.isBuy
                            ? pricing.upper
                            : pricing.lower;
                    }

                    UD60x18 premium;

                    {
                        UD60x18 quoteAMMPrice = l.marketPrice.avg(
                            nextMarketPrice
                        );

                        premium = quoteAMMPrice * tradeSize;
                    }
                    UD60x18 takerFee = _takerFee(l, tradeSize, premium, true);

                    // Denormalize premium
                    premium = Position.contractsToCollateral(
                        premium,
                        l.strike,
                        l.isCallPool
                    );

                    // Update price and liquidity variables
                    {
                        UD60x18 protocolFee = takerFee *
                            PROTOCOL_FEE_PERCENTAGE;

                        UD60x18 makerRebate = takerFee - protocolFee;
                        _updateGlobalFeeRate(l, makerRebate);

                        vars.totalProtocolFees =
                            vars.totalProtocolFees +
                            protocolFee;
                        l.protocolFees = l.protocolFees + protocolFee;
                    }

                    // is_buy: taker has to pay premium + fees
                    // ~is_buy: taker receives premium - fees
                    vars.totalPremium =
                        vars.totalPremium +
                        (args.isBuy ? premium + takerFee : premium - takerFee);
                    vars.totalTakerFees = vars.totalTakerFees + takerFee;

                    l.marketPrice = nextMarketPrice;
                }

                UD60x18 dist = (l.marketPrice.intoSD59x18() -
                    oldMarketPrice.intoSD59x18()).abs().intoUD60x18();

                vars.shortDelta =
                    vars.shortDelta +
                    (l.shortRate * dist) /
                    PoolStorage.MIN_TICK_DISTANCE;
                vars.longDelta =
                    vars.longDelta +
                    (l.longRate * dist) /
                    PoolStorage.MIN_TICK_DISTANCE;

                if (maxSize >= remaining) {
                    remaining = ZERO;
                } else {
                    // The trade will require crossing into the next tick range
                    if (
                        args.isBuy &&
                        l.tickIndex.next(l.currentTick) >=
                        Pricing.MAX_TICK_PRICE
                    ) revert Pool__InsufficientAskLiquidity();

                    if (!args.isBuy && l.currentTick <= Pricing.MIN_TICK_PRICE)
                        revert Pool__InsufficientBidLiquidity();

                    remaining = remaining - tradeSize;
                    _cross(args.isBuy);
                }
            }
        }

        totalPremium = l.toPoolTokenDecimals(vars.totalPremium);

        _ensureBelowTradeMaxSlippage(
            totalPremium,
            args.premiumLimit,
            args.isBuy
        );

        delta = _calculateAndUpdateUserAssets(
            l,
            args.user,
            vars.totalPremium,
            args.size,
            args.isBuy,
            args.creditAmount,
            args.transferCollateralToUser,
            permit
        );

        if (args.isBuy) {
            if (vars.shortDelta > ZERO)
                _mint(address(this), PoolStorage.SHORT, vars.shortDelta);

            if (vars.longDelta > ZERO)
                _burn(address(this), PoolStorage.LONG, vars.longDelta);
        } else {
            if (vars.longDelta > ZERO)
                _mint(address(this), PoolStorage.LONG, vars.longDelta);

            if (vars.shortDelta > ZERO)
                _burn(address(this), PoolStorage.SHORT, vars.shortDelta);
        }

        emit Trade(
            args.user,
            args.size,
            delta,
            args.isBuy
                ? vars.totalPremium - vars.totalTakerFees
                : vars.totalPremium,
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
        UD60x18 currentTick = l.currentTick;

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
        UD60x18 size,
        bool isBuy
    ) internal view returns (Position.Delta memory delta) {
        UD60x18 longs = _balanceOfUD60x18(user, PoolStorage.LONG);
        UD60x18 shorts = _balanceOfUD60x18(user, PoolStorage.SHORT);

        if (isBuy) {
            delta.shorts = -PRBMathExtra.min(shorts, size).intoSD59x18();
            delta.longs = size.intoSD59x18() + delta.shorts;
        } else {
            delta.longs = -PRBMathExtra.min(longs, size).intoSD59x18();
            delta.shorts = size.intoSD59x18() + delta.longs;
        }
    }

    // @notice Calculate the asset update for a user and update the user's assets
    function _calculateAndUpdateUserAssets(
        PoolStorage.Layout storage l,
        address user,
        UD60x18 totalPremium,
        UD60x18 size,
        bool isBuy,
        uint256 creditAmount,
        bool transferCollateralToUser,
        Permit2.Data memory permit
    ) internal returns (Position.Delta memory delta) {
        delta = _calculateAssetsUpdate(l, user, totalPremium, size, isBuy);

        _updateUserAssets(
            l,
            user,
            delta,
            creditAmount,
            transferCollateralToUser,
            permit
        );
    }

    function _calculateAssetsUpdate(
        PoolStorage.Layout storage l,
        address user,
        UD60x18 totalPremium,
        UD60x18 size,
        bool isBuy
    ) internal view returns (Position.Delta memory delta) {
        delta = _getTradeDelta(user, size, isBuy);

        bool _isBuy = delta.longs > iZERO || delta.shorts < iZERO;

        UD60x18 shortCollateral = Position.contractsToCollateral(
            delta.shorts.abs().intoUD60x18(),
            l.strike,
            l.isCallPool
        );

        SD59x18 iShortCollateral = shortCollateral.intoSD59x18();
        if (delta.shorts < iZERO) {
            iShortCollateral = -iShortCollateral;
        }

        if (_isBuy) {
            delta.collateral =
                -PRBMathExtra.min(iShortCollateral, iZERO) -
                totalPremium.intoSD59x18();
        } else {
            delta.collateral =
                totalPremium.intoSD59x18() -
                PRBMathExtra.max(iShortCollateral, iZERO);
        }

        return delta;
    }

    /// @notice Execute a trade by transferring the net change in short and long option
    ///         contracts and collateral to / from an agent.
    function _updateUserAssets(
        PoolStorage.Layout storage l,
        address user,
        Position.Delta memory delta,
        uint256 creditAmount,
        bool transferCollateralToUser,
        Permit2.Data memory permit
    ) internal {
        if (
            (delta.longs == iZERO && delta.shorts == iZERO) ||
            (delta.longs > iZERO && delta.shorts > iZERO) ||
            (delta.longs < iZERO && delta.shorts < iZERO)
        ) revert Pool__InvalidAssetUpdate(delta.longs, delta.shorts);

        // We create a new `_deltaCollateral` variable instead of adding `creditAmount` to `delta.collateral`,
        // as we will return `delta`, and want `delta.collateral` to reflect the absolute collateral change resulting from this update
        int256 _deltaCollateral = l.toPoolTokenDecimals(delta.collateral);
        if (creditAmount > 0) {
            _deltaCollateral = _deltaCollateral + creditAmount.toInt256();
        }

        // Transfer collateral
        if (_deltaCollateral < 0) {
            _transferFromWithPermitOrRouter(
                permit,
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
        if (delta.longs < iZERO) {
            _burn(user, PoolStorage.LONG, (-delta.longs).intoUD60x18());
        } else if (delta.longs > iZERO) {
            _mint(user, PoolStorage.LONG, delta.longs.intoUD60x18());
        }

        // Transfer short
        if (delta.shorts < iZERO) {
            _burn(user, PoolStorage.SHORT, (-delta.shorts).intoUD60x18());
        } else if (delta.shorts > iZERO) {
            _mint(user, PoolStorage.SHORT, delta.shorts.intoUD60x18());
        }
    }

    function _calculateQuoteRFQPremiumAndFee(
        PoolStorage.Layout storage l,
        UD60x18 size,
        UD60x18 price,
        bool isBuy
    ) internal view returns (PremiumAndFeeInternal memory r) {
        r.premium = price * size;
        r.protocolFee = _takerFee(l, size, r.premium, true);

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
    ///         An LP can create a RFQ quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    /// @param args The fillQuoteRFQ parameters
    /// @param quoteRFQ The RFQ quote given by the provider
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return premiumTaker The premium paid by the taker (poolToken decimals)
    /// @return deltaTaker The net collateral / longs / shorts change for taker of the trade.
    function _fillQuoteRFQ(
        FillQuoteRFQArgsInternal memory args,
        QuoteRFQ memory quoteRFQ,
        Permit2.Data memory permit
    )
        internal
        returns (uint256 premiumTaker, Position.Delta memory deltaTaker)
    {
        if (args.size > quoteRFQ.size)
            revert Pool__AboveQuoteSize(args.size, quoteRFQ.size);

        bytes32 quoteRFQHash;
        PremiumAndFeeInternal memory premiumAndFee;
        Position.Delta memory deltaMaker;

        {
            PoolStorage.Layout storage l = PoolStorage.layout();
            quoteRFQHash = _quoteRFQHash(quoteRFQ);
            _ensureQuoteRFQIsValid(l, args, quoteRFQ, quoteRFQHash);

            premiumAndFee = _calculateQuoteRFQPremiumAndFee(
                l,
                args.size,
                quoteRFQ.price,
                quoteRFQ.isBuy
            );

            // Update amount filled for this quote
            l.quoteRFQAmountFilled[quoteRFQ.provider][quoteRFQHash] =
                l.quoteRFQAmountFilled[quoteRFQ.provider][quoteRFQHash] +
                args.size;

            // Update protocol fees
            l.protocolFees = l.protocolFees + premiumAndFee.protocolFee;

            // Process trade taker
            deltaTaker = _calculateAndUpdateUserAssets(
                l,
                args.user,
                premiumAndFee.premiumTaker,
                args.size,
                !quoteRFQ.isBuy,
                args.creditAmount,
                args.transferCollateralToUser,
                permit
            );

            // Process trade maker
            deltaMaker = _calculateAndUpdateUserAssets(
                l,
                quoteRFQ.provider,
                premiumAndFee.premiumMaker,
                args.size,
                quoteRFQ.isBuy,
                0,
                true,
                Permit2.emptyPermit()
            );
        }

        emit FillQuoteRFQ(
            quoteRFQHash,
            args.user,
            quoteRFQ.provider,
            args.size,
            deltaMaker,
            deltaTaker,
            premiumAndFee.premium,
            premiumAndFee.protocolFee,
            !quoteRFQ.isBuy
        );

        return (
            PoolStorage.layout().toPoolTokenDecimals(
                premiumAndFee.premiumTaker
            ),
            deltaTaker
        );
    }

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
    ///         NOTE: This function can be called post or prior to expiration.
    function _annihilate(address owner, UD60x18 size) internal {
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
        Position.KeyInternal memory srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) internal {
        if (srcP.owner == newOwner && srcP.operator == newOperator)
            revert Pool__InvalidTransfer();

        if (size == ZERO) revert Pool__ZeroSize();

        PoolStorage.Layout storage l = PoolStorage.layout();

        Position.KeyInternal memory dstP = Position.KeyInternal({
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

        UD60x18 balance = _balanceOfUD60x18(srcP.owner, srcTokenId);
        if (size > balance) revert Pool__NotEnoughTokens(balance, size);

        UD60x18 proportionTransferred = size.div(balance);

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

        {
            UD60x18 feesTransferred = proportionTransferred *
                srcData.claimableFees;
            dstData.claimableFees = dstData.claimableFees + feesTransferred;
            srcData.claimableFees = srcData.claimableFees + feesTransferred;
        }

        if (srcData.lastDeposit > dstData.lastDeposit) {
            dstData.lastDeposit = srcData.lastDeposit;
        }

        if (srcTokenId == dstTokenId) {
            _safeTransfer(
                address(this),
                srcP.owner,
                newOwner,
                srcTokenId,
                size.unwrap(),
                ""
            );
        } else {
            _burn(srcP.owner, srcTokenId, size);
            _mint(newOwner, dstTokenId, size);
        }

        if (size == balance) delete l.positions[srcKey];

        emit TransferPosition(srcP.owner, newOwner, srcTokenId, dstTokenId);
    }

    function _calculateExerciseValue(
        PoolStorage.Layout storage l,
        UD60x18 size
    ) internal returns (UD60x18) {
        if (size == ZERO) return ZERO;

        UD60x18 settlementPrice = l.getSettlementPrice();
        UD60x18 strike = l.strike;
        bool isCall = l.isCallPool;

        UD60x18 intrinsicValue;
        if (isCall && settlementPrice > strike) {
            intrinsicValue = settlementPrice - strike;
        } else if (!isCall && settlementPrice < strike) {
            intrinsicValue = strike - settlementPrice;
        } else {
            return ZERO;
        }

        UD60x18 exerciseValue = size * intrinsicValue;

        if (isCall) {
            exerciseValue = exerciseValue.div(settlementPrice);
        }

        return exerciseValue;
    }

    function _calculateCollateralValue(
        PoolStorage.Layout storage l,
        UD60x18 size,
        UD60x18 exerciseValue
    ) internal view returns (UD60x18) {
        return
            l.isCallPool
                ? size - exerciseValue
                : size * l.strike - exerciseValue;
    }

    /// @notice Exercises all long options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function _exercise(address holder) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureExpired(l);

        if (l.protocolFees > ZERO) _claimProtocolFees();

        UD60x18 size = _balanceOfUD60x18(holder, PoolStorage.LONG);
        if (size == ZERO) return 0;

        UD60x18 exerciseValue = _calculateExerciseValue(l, size);

        _removeFromFactory(l);

        _burn(holder, PoolStorage.LONG, size);

        if (exerciseValue > ZERO) {
            IERC20(l.getPoolToken()).safeTransfer(holder, exerciseValue);
        }

        emit Exercise(holder, size, exerciseValue, l.settlementPrice, ZERO);

        return l.toPoolTokenDecimals(exerciseValue);
    }

    /// @notice Settles all short options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function _settle(address holder) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureExpired(l);

        if (l.protocolFees > ZERO) _claimProtocolFees();

        UD60x18 size = _balanceOfUD60x18(holder, PoolStorage.SHORT);
        if (size == ZERO) return 0;

        UD60x18 exerciseValue = _calculateExerciseValue(l, size);
        UD60x18 collateralValue = _calculateCollateralValue(
            l,
            size,
            exerciseValue
        );

        _removeFromFactory(l);

        // Burn short and transfer collateral to operator
        _burn(holder, PoolStorage.SHORT, size);
        if (collateralValue > ZERO) {
            IERC20(l.getPoolToken()).safeTransfer(holder, collateralValue);
        }

        emit Settle(holder, size, exerciseValue, l.settlementPrice, ZERO);

        return l.toPoolTokenDecimals(collateralValue);
    }

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    function _settlePosition(
        Position.KeyInternal memory p
    ) internal returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureExpired(l);
        _removeFromFactory(l);

        if (l.protocolFees > ZERO) _claimProtocolFees();

        Position.Data storage pData = l.positions[p.keyHash()];

        Tick memory lowerTick = _getTick(p.lower);
        Tick memory upperTick = _getTick(p.upper);

        uint256 tokenId = PoolStorage.formatTokenId(
            p.operator,
            p.lower,
            p.upper,
            p.orderType
        );

        UD60x18 size = _balanceOfUD60x18(p.owner, tokenId);
        if (size == ZERO) return 0;

        {
            // Update claimable fees
            UD60x18 feeRate = _rangeFeeRate(
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

        UD60x18 claimableFees;
        UD60x18 payoff;
        UD60x18 collateral;

        {
            UD60x18 longs = p.long(size, l.marketPrice);
            UD60x18 shorts = p.short(size, l.marketPrice);

            claimableFees = pData.claimableFees;
            payoff = _calculateExerciseValue(l, ONE);
            collateral = p.collateral(size, l.marketPrice);
            collateral = collateral + longs * payoff;
            collateral =
                collateral +
                shorts *
                ((l.isCallPool ? ONE : l.strike) - payoff);

            collateral = collateral + claimableFees;

            _burn(p.owner, tokenId, size);

            if (longs > ZERO) {
                _burn(address(this), PoolStorage.LONG, longs);
            }

            if (shorts > ZERO) {
                _burn(address(this), PoolStorage.SHORT, shorts);
            }
        }

        pData.claimableFees = ZERO;
        pData.lastFeeRate = ZERO;

        if (collateral > ZERO) {
            IERC20(l.getPoolToken()).safeTransfer(p.operator, collateral);
        }

        emit SettlePosition(
            p.owner,
            tokenId,
            size,
            collateral - claimableFees,
            payoff,
            claimableFees,
            l.settlementPrice,
            ZERO
        );

        return l.toPoolTokenDecimals(collateral);
    }

    /// @notice Wraps native token if the pool is using WRAPPED_NATIVE_TOKEN
    /// @return wrappedAmount The amount of native tokens wrapped
    function _wrapNativeToken() internal returns (uint256 wrappedAmount) {
        if (msg.value > 0) {
            if (PoolStorage.layout().getPoolToken() != WRAPPED_NATIVE_TOKEN)
                revert Pool__NotWrappedNativeTokenPool();

            IWETH(WRAPPED_NATIVE_TOKEN).deposit{value: msg.value}();
            wrappedAmount = msg.value;
        }
    }

    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////

    ////////////////
    // TickSystem //
    ////////////////
    // ToDo : Reorganize those functions ?

    function _getNearestTicksBelow(
        UD60x18 lower,
        UD60x18 upper
    )
        internal
        view
        returns (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper)
    {
        Position.ensureLowerGreaterOrEqualUpper(lower, upper);

        nearestBelowLower = _getNearestTickBelow(lower);
        nearestBelowUpper = _getNearestTickBelow(upper);

        // If no tick between `lower` and `upper`, then the nearest tick below `upper`, will be `lower`
        if (nearestBelowUpper == nearestBelowLower) {
            nearestBelowUpper = lower;
        }
    }

    /// @notice Gets the nearest tick that is less than or equal to `price`.
    function _getNearestTickBelow(
        UD60x18 price
    ) internal view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 left = l.currentTick;

        while (left != ZERO && left > price) {
            left = l.tickIndex.prev(left);
        }

        UD60x18 next = l.tickIndex.next(left);
        while (left != ZERO && next <= price) {
            left = next;
            next = l.tickIndex.next(left);
        }

        if (left == ZERO) revert Pool__TickNotFound(price);

        return left;
    }

    /// @notice Get a tick, reverts if tick is not found
    function _getTick(UD60x18 price) internal view returns (Tick memory) {
        (Tick memory tick, bool tickFound) = _tryGetTick(price);
        if (!tickFound) revert Pool__TickNotFound(price);

        return tick;
    }

    /// @notice Try to get tick, does not revert if tick is not found
    function _tryGetTick(
        UD60x18 price
    ) internal view returns (Tick memory tick, bool tickFound) {
        _verifyTickWidth(price);

        if (price < Pricing.MIN_TICK_PRICE || price > Pricing.MAX_TICK_PRICE)
            revert Pool__TickOutOfRange(price);

        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.contains(price)) return (l.ticks[price], true);

        return (
            Tick({
                delta: iZERO,
                externalFeeRate: ZERO,
                longDelta: iZERO,
                shortDelta: iZERO,
                counter: 0
            }),
            false
        );
    }

    /// @notice Creates a Tick for a given price, or returns the existing tick.
    /// @param price The price of the Tick (18 decimals)
    /// @param priceBelow The price of the nearest Tick below (18 decimals)
    /// @return tick The Tick for a given price
    function _getOrCreateTick(
        UD60x18 price,
        UD60x18 priceBelow
    ) internal returns (Tick memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        (Tick memory tick, bool tickFound) = _tryGetTick(price);

        if (tickFound) return tick;

        if (
            !l.tickIndex.contains(priceBelow) ||
            l.tickIndex.next(priceBelow) <= price
        ) revert Pool__InvalidBelowPrice(price, priceBelow);

        tick = Tick({
            delta: iZERO,
            externalFeeRate: price <= l.marketPrice ? l.globalFeeRate : ZERO,
            longDelta: iZERO,
            shortDelta: iZERO,
            counter: 0
        });

        l.tickIndex.insertAfter(priceBelow, price);
        l.ticks[price] = tick;

        return tick;
    }

    /// @notice Removes a tick if it does not mark the beginning or the end of a range order.
    function _removeTickIfNotActive(UD60x18 price) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (!l.tickIndex.contains(price)) return;

        Tick storage tick = l.ticks[price];

        if (
            price > Pricing.MIN_TICK_PRICE &&
            price < Pricing.MAX_TICK_PRICE &&
            tick.counter == 0 // Can only remove an active tick if no active range order marks a starting / ending tick on this tick.
        ) {
            if (tick.delta != iZERO) revert Pool__TickDeltaNotZero(tick.delta);

            if (price == l.currentTick) {
                UD60x18 newCurrentTick = l.tickIndex.prev(price);

                if (newCurrentTick < Pricing.MIN_TICK_PRICE)
                    revert Pool__TickOutOfRange(newCurrentTick);

                l.currentTick = newCurrentTick;
            }

            l.tickIndex.remove(price);
            delete l.ticks[price];
        }
    }

    function _updateTicks(
        UD60x18 lower,
        UD60x18 upper,
        UD60x18 marketPrice,
        SD59x18 delta,
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
            lowerTick.delta = lowerTick.delta - delta;
            upperTick.delta = upperTick.delta + delta;

            if (orderType.isLong()) {
                lowerTick.longDelta = lowerTick.longDelta - delta;
                upperTick.longDelta = upperTick.longDelta + delta;
            } else {
                lowerTick.shortDelta = lowerTick.shortDelta - delta;
                upperTick.shortDelta = upperTick.shortDelta + delta;
            }
        } else if (lower > l.currentTick) {
            lowerTick.delta = lowerTick.delta + delta;
            upperTick.delta = upperTick.delta - delta;

            if (orderType.isLong()) {
                lowerTick.longDelta = lowerTick.longDelta + delta;
                upperTick.longDelta = upperTick.longDelta - delta;
            } else {
                lowerTick.shortDelta = lowerTick.shortDelta + delta;
                upperTick.shortDelta = upperTick.shortDelta - delta;
            }
        } else {
            lowerTick.delta = lowerTick.delta - delta;
            upperTick.delta = upperTick.delta - delta;
            l.liquidityRate = l.liquidityRate.add(delta);

            if (orderType.isLong()) {
                lowerTick.longDelta = lowerTick.longDelta - delta;
                upperTick.longDelta = upperTick.longDelta - delta;
                l.longRate = l.longRate.add(delta);
            } else {
                lowerTick.shortDelta = lowerTick.shortDelta - delta;
                upperTick.shortDelta = upperTick.shortDelta - delta;
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
        if (delta > iZERO) {
            uint256 crossings;

            while (l.tickIndex.next(l.currentTick) < marketPrice) {
                _cross(true);
                crossings++;
            }

            while (l.currentTick > marketPrice) {
                _cross(false);
                crossings++;
            }

            if (crossings > 2) revert Pool__InvalidReconciliation(crossings);
        }

        emit UpdateTick(
            lower,
            l.tickIndex.prev(lower),
            l.tickIndex.next(lower),
            lowerTick.delta,
            lowerTick.externalFeeRate,
            lowerTick.longDelta,
            lowerTick.shortDelta,
            lowerTick.counter
        );

        emit UpdateTick(
            upper,
            l.tickIndex.prev(upper),
            l.tickIndex.next(upper),
            upperTick.delta,
            upperTick.externalFeeRate,
            upperTick.longDelta,
            upperTick.shortDelta,
            upperTick.counter
        );

        if (delta <= iZERO) {
            _removeTickIfNotActive(lower);
            _removeTickIfNotActive(upper);
        }
    }

    function _updateGlobalFeeRate(
        PoolStorage.Layout storage l,
        UD60x18 makerRebate
    ) internal {
        if (l.liquidityRate == ZERO) return;
        l.globalFeeRate = l.globalFeeRate + (makerRebate / l.liquidityRate);
    }

    function _cross(bool isBuy) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (isBuy) {
            UD60x18 right = l.tickIndex.next(l.currentTick);
            if (right >= Pricing.MAX_TICK_PRICE)
                revert Pool__TickOutOfRange(right);
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

        emit UpdateTick(
            l.currentTick,
            l.tickIndex.prev(l.currentTick),
            l.tickIndex.next(l.currentTick),
            currentTick.delta,
            currentTick.externalFeeRate,
            currentTick.longDelta,
            currentTick.shortDelta,
            currentTick.counter
        );

        if (!isBuy) {
            if (l.currentTick <= Pricing.MIN_TICK_PRICE)
                revert Pool__TickOutOfRange(l.currentTick);
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
        UD60x18 lower,
        UD60x18 upper,
        UD60x18 lowerTickExternalFeeRate,
        UD60x18 upperTickExternalFeeRate
    ) internal view returns (UD60x18) {
        UD60x18 aboveFeeRate = l.currentTick >= upper
            ? l.globalFeeRate - upperTickExternalFeeRate
            : upperTickExternalFeeRate;

        UD60x18 belowFeeRate = l.currentTick >= lower
            ? lowerTickExternalFeeRate
            : l.globalFeeRate - lowerTickExternalFeeRate;

        return l.globalFeeRate - aboveFeeRate - belowFeeRate;
    }

    /// @notice Gets the lower and upper bound of the stranded market area when it
    ///         exists. In case the stranded market area does not exist it will return
    ///         s the stranded market area the maximum tick price for both the lower
    ///         and the upper, in which case the market price is not stranded given
    ///         any range order info order.
    /// @return lower Lower bound of the stranded market price area (Default : 1e18) (18 decimals)
    /// @return upper Upper bound of the stranded market price area (Default : 1e18) (18 decimals)
    function _getStrandedArea(
        PoolStorage.Layout storage l
    ) internal view returns (UD60x18 lower, UD60x18 upper) {
        lower = ONE;
        upper = ONE;

        UD60x18 current = l.currentTick;
        UD60x18 right = l.tickIndex.next(current);

        if (l.liquidityRate == ZERO) {
            // applies whenever the pool is empty or the last active order that
            // was traversed by the price was withdrawn
            // the check is independent of the current market price
            lower = current;
            upper = right;
        } else if (
            -l.ticks[right].delta > iZERO &&
            l.liquidityRate == (-l.ticks[right].delta).intoUD60x18() &&
            right == l.marketPrice &&
            l.tickIndex.next(right) != ZERO
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
            -l.ticks[current].delta > iZERO &&
            l.liquidityRate == (-l.ticks[current].delta).intoUD60x18() &&
            current == l.marketPrice &&
            l.tickIndex.prev(current) != ZERO
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
        Position.KeyInternal memory p,
        bool isBid
    ) internal view returns (bool) {
        (UD60x18 lower, UD60x18 upper) = _getStrandedArea(l);
        UD60x18 tick = isBid ? p.upper : p.lower;
        return lower <= tick && tick <= upper;
    }

    /// @notice In case the market price is stranded the market price needs to be
    ///         set to the upper (lower) tick of the bid (ask) order. See docstring of
    ///         isMarketPriceStranded.
    function _getStrandedMarketPriceUpdate(
        Position.KeyInternal memory p,
        bool isBid
    ) internal pure returns (UD60x18) {
        return isBid ? p.upper : p.lower;
    }

    function _verifyTickWidth(UD60x18 price) internal pure {
        if (price % Pricing.MIN_TICK_DISTANCE != ZERO)
            revert Pool__TickWidthInvalid(price);
    }

    function _quoteRFQHash(
        IPoolInternal.QuoteRFQ memory quoteRFQ
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                FILL_QUOTE_RFQ_TYPE_HASH,
                quoteRFQ.provider,
                quoteRFQ.taker,
                quoteRFQ.price,
                quoteRFQ.size,
                quoteRFQ.isBuy,
                quoteRFQ.deadline,
                quoteRFQ.salt
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

    function _balanceOfUD60x18(
        address user,
        uint256 tokenId
    ) internal view returns (UD60x18) {
        return UD60x18.wrap(_balanceOf(user, tokenId));
    }

    function _mint(address account, uint256 id, UD60x18 amount) internal {
        _mint(account, id, amount.unwrap(), "");
    }

    function _burn(address account, uint256 id, UD60x18 amount) internal {
        _burn(account, id, amount.unwrap());
    }

    function _transferFromWithPermitOrRouter(
        Permit2.Data memory permit,
        address token,
        address owner,
        address to,
        UD60x18 amount
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _transferFromWithPermitOrRouter(
            permit,
            token,
            owner,
            to,
            l.toPoolTokenDecimals(amount)
        );
    }

    function _transferFromWithPermitOrRouter(
        Permit2.Data memory permit,
        address token,
        address owner,
        address to,
        uint256 amount
    ) internal {
        if (permit.signature.length > 0) {
            if (permit.permittedToken != token)
                revert Pool__InvalidPermittedToken(
                    permit.permittedToken,
                    token
                );

            if (permit.permittedAmount < amount)
                revert Pool__InsufficientPermit(amount, permit.permittedAmount);

            Permit2.permitTransferFrom(permit, owner, to, amount);
        } else {
            IERC20Router(ROUTER).safeTransferFrom(token, owner, to, amount);
        }
    }

    function _ensureValidRange(UD60x18 lower, UD60x18 upper) internal pure {
        if (
            lower == ZERO ||
            upper == ZERO ||
            lower >= upper ||
            lower < Pricing.MIN_TICK_PRICE ||
            upper > Pricing.MAX_TICK_PRICE
        ) revert Pool__InvalidRange(lower, upper);
    }

    function _ensureNonZeroSize(UD60x18 size) internal pure {
        if (size == ZERO) revert Pool__ZeroSize();
    }

    function _ensureExpired(PoolStorage.Layout storage l) internal view {
        if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();
    }

    function _ensureNotExpired(PoolStorage.Layout storage l) internal view {
        if (block.timestamp >= l.maturity) revert Pool__OptionExpired();
    }

    function _ensureWithdrawalDelayElapsed(
        Position.Data storage position
    ) internal view {
        uint256 unlockTime = position.lastDeposit + WITHDRAWAL_DELAY;
        if (block.timestamp < unlockTime)
            revert Pool__WithdrawalDelayNotElapsed(unlockTime);
    }

    function _ensureBelowTradeMaxSlippage(
        uint256 totalPremium,
        uint256 premiumLimit,
        bool isBuy
    ) internal pure {
        if (isBuy && totalPremium > premiumLimit)
            revert Pool__AboveMaxSlippage(premiumLimit, 0, totalPremium);
        if (!isBuy && totalPremium < premiumLimit)
            revert Pool__AboveMaxSlippage(
                premiumLimit,
                totalPremium,
                type(uint256).max
            );
    }

    function _ensureBelowDepositWithdrawMaxSlippage(
        UD60x18 marketPrice,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) internal pure {
        if (marketPrice > maxMarketPrice || marketPrice < minMarketPrice)
            revert Pool__AboveMaxSlippage(
                marketPrice.unwrap(),
                minMarketPrice.unwrap(),
                maxMarketPrice.unwrap()
            );
    }

    function _areQuoteRFQAndBalanceValid(
        PoolStorage.Layout storage l,
        FillQuoteRFQArgsInternal memory args,
        QuoteRFQ memory quoteRFQ,
        bytes32 quoteRFQHash
    ) internal view returns (bool isValid, InvalidQuoteRFQError error) {
        (isValid, error) = _isQuoteRFQValid(
            l,
            args,
            quoteRFQ,
            quoteRFQHash,
            false
        );
        if (!isValid) {
            return (isValid, error);
        }
        return _isQuoteRFQBalanceValid(l, args, quoteRFQ);
    }

    function _ensureQuoteRFQIsValid(
        PoolStorage.Layout storage l,
        FillQuoteRFQArgsInternal memory args,
        QuoteRFQ memory quoteRFQ,
        bytes32 quoteRFQHash
    ) internal view {
        _isQuoteRFQValid(l, args, quoteRFQ, quoteRFQHash, true);
    }

    function _isQuoteRFQValid(
        PoolStorage.Layout storage l,
        FillQuoteRFQArgsInternal memory args,
        QuoteRFQ memory quoteRFQ,
        bytes32 quoteRFQHash,
        bool revertIfInvalid
    ) internal view returns (bool, InvalidQuoteRFQError) {
        if (block.timestamp > quoteRFQ.deadline) {
            if (revertIfInvalid) revert Pool__QuoteRFQExpired();
            return (false, InvalidQuoteRFQError.QuoteRFQExpired);
        }

        UD60x18 filledAmount = l.quoteRFQAmountFilled[quoteRFQ.provider][
            quoteRFQHash
        ];

        if (filledAmount.unwrap() == type(uint256).max) {
            if (revertIfInvalid) revert Pool__QuoteRFQCancelled();
            return (false, InvalidQuoteRFQError.QuoteRFQCancelled);
        }

        if (filledAmount + args.size > quoteRFQ.size) {
            if (revertIfInvalid)
                revert Pool__QuoteRFQOverfilled(
                    filledAmount,
                    args.size,
                    quoteRFQ.size
                );
            return (false, InvalidQuoteRFQError.QuoteRFQOverfilled);
        }

        if (
            Pricing.MIN_TICK_PRICE > quoteRFQ.price ||
            quoteRFQ.price > Pricing.MAX_TICK_PRICE
        ) {
            if (revertIfInvalid) revert Pool__OutOfBoundsPrice(quoteRFQ.price);
            return (false, InvalidQuoteRFQError.OutOfBoundsPrice);
        }

        if (quoteRFQ.taker != address(0) && args.user != quoteRFQ.taker) {
            if (revertIfInvalid) revert Pool__InvalidQuoteRFQTaker();
            return (false, InvalidQuoteRFQError.InvalidQuoteRFQTaker);
        }

        address signer = ECDSA.recover(
            quoteRFQHash,
            args.signature.v,
            args.signature.r,
            args.signature.s
        );
        if (signer != quoteRFQ.provider) {
            if (revertIfInvalid) revert Pool__InvalidQuoteRFQSignature();
            return (false, InvalidQuoteRFQError.InvalidQuoteRFQSignature);
        }

        return (true, InvalidQuoteRFQError.None);
    }

    function _isQuoteRFQBalanceValid(
        PoolStorage.Layout storage l,
        FillQuoteRFQArgsInternal memory args,
        QuoteRFQ memory quoteRFQ
    ) internal view returns (bool, InvalidQuoteRFQError) {
        PremiumAndFeeInternal
            memory premiumAndFee = _calculateQuoteRFQPremiumAndFee(
                l,
                args.size,
                quoteRFQ.price,
                quoteRFQ.isBuy
            );

        Position.Delta memory delta = _calculateAssetsUpdate(
            l,
            args.user,
            premiumAndFee.premium,
            args.size,
            quoteRFQ.isBuy
        );

        if (
            (delta.longs == iZERO && delta.shorts == iZERO) ||
            (delta.longs > iZERO && delta.shorts > iZERO) ||
            (delta.longs < iZERO && delta.shorts < iZERO)
        ) return (false, InvalidQuoteRFQError.InvalidAssetUpdate);

        if (delta.collateral < iZERO) {
            IERC20 token = IERC20(l.getPoolToken());
            if (
                token.allowance(args.user, ROUTER) <
                l.toPoolTokenDecimals((-delta.collateral).intoUD60x18())
            ) {
                return (
                    false,
                    InvalidQuoteRFQError.InsufficientCollateralAllowance
                );
            }

            if (
                token.balanceOf(args.user) <
                l.toPoolTokenDecimals((-delta.collateral).intoUD60x18())
            ) {
                return (
                    false,
                    InvalidQuoteRFQError.InsufficientCollateralBalance
                );
            }
        }

        if (
            delta.longs < iZERO &&
            _balanceOf(args.user, PoolStorage.LONG) <
            (-delta.longs).intoUD60x18().unwrap()
        ) {
            return (false, InvalidQuoteRFQError.InsufficientLongBalance);
        }

        if (
            delta.shorts < iZERO &&
            _balanceOf(args.user, PoolStorage.SHORT) <
            (-delta.shorts).intoUD60x18().unwrap()
        ) {
            return (false, InvalidQuoteRFQError.InsufficientShortBalance);
        }

        return (true, InvalidQuoteRFQError.None);
    }

    function _ensureOperator(address operator) internal view {
        if (operator != msg.sender) revert Pool__NotAuthorized(msg.sender);
    }
}
