// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolInternal} from "./IPoolInternal.sol";
import {Position} from "../libraries/Position.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

interface IPoolCore is IPoolInternal {
    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param size The size of a trade (number of contracts)
    /// @param normalizedPremium The total cost of option(s) for a purchase (Normalized by strike)
    /// @return The taker fee for an option trade
    function takerFee(
        uint256 size,
        uint256 normalizedPremium
    ) external pure returns (uint256);

    /// @notice Returns all pool parameters used for deployment
    /// @return base Address of base token
    /// @return quote Address of quote token
    /// @return baseOracle Address of base token price feed
    /// @return quoteOracle Address of quote token price feed
    /// @return strike The strike of the option
    /// @return maturity The maturity timestamp of the option
    /// @return isCallPool Whether the pool is for call or put options
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address quote,
            address baseOracle,
            address quoteOracle,
            uint256 strike,
            uint64 maturity,
            bool isCallPool
        );

    /// @notice Gives a quote for a trade
    /// @param size The number of contracts being traded
    /// @param isBuy Whether the taker is buying or selling
    /// @return The premium which has to be paid to complete the trade
    function getTradeQuote(
        uint256 size,
        bool isBuy
    ) external view returns (uint256);

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    /// @param p The position key
    function claim(Position.Key memory p) external;

    /// @notice Returns total claimable fees for the position
    /// @param p The position key
    /// @return The total claimable fees for the position
    function getClaimableFees(
        Position.Key memory p
    ) external view returns (uint256);

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage
    ) external;

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage,
        bool isBidIfStrandedMarketPrice
    ) external;

    /// @notice Swap tokens and deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param s The swap arguments
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    function swapAndDeposit(
        IPoolInternal.SwapArgs memory s,
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage
    ) external payable;

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    /// @param p The position key
    /// @param size The position size to withdraw
    /// @param maxSlippage Max slippage (Percentage with 18 decimals -> 1% = 1e16)
    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 maxSlippage
    ) external;

    /// @notice Functionality to support the RFQ / OTC system.
    ///         An LP can create a quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    /// @param tradeQuote The quote given by the provider
    /// @param size The size to fill from the quote
    /// @param signature  secp256k1 concatenated 'r', 's', and 'v' value
    function fillQuote(
        TradeQuote memory tradeQuote,
        uint256 size,
        Signature memory signature
    ) external;

    /// @notice Underwrite an option by depositing collateral
    /// @param underwrite The underwriter of the option (Collateral will be taken from this address, and it will receive the short token)
    /// @param longReceiver The address which will receive the long token
    /// @param size The number of contracts being underwritten
    function writeFrom(
        address underwriter,
        address longReceiver,
        uint256 size
    ) external;

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    /// @param size The number of contracts being traded
    /// @param isBuy Whether the taker is buying or selling
    /// @return totalPremium The premium paid or received by the taker for the trade
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function trade(
        uint256 size,
        bool isBuy
    ) external returns (uint256 totalPremium, Delta memory delta);

    /// @notice Swap tokens and completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    /// @param s The swap arguments
    /// @param size The number of contracts being traded
    /// @param isBuy Whether the taker is buying or selling
    /// @return totalPremium The premium paid or received by the taker for the trade
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    /// @return swapOutAmount The amount of pool tokens resulting from the swap
    function swapAndTrade(
        IPoolInternal.SwapArgs memory s,
        uint256 size,
        bool isBuy
    )
        external
        payable
        returns (
            uint256 totalPremium,
            Delta memory delta,
            uint256 swapOutAmount
        );

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool, and swap the resulting collateral to another token
    /// @param s The swap arguments
    /// @param size The number of contracts being traded
    /// @param isBuy Whether the taker is buying or selling
    /// @return totalPremium The premium received by the taker of the trade
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    /// @return collateralReceived The amount of un-swapped collateral received from the trade.
    /// @return tokenOutReceived The final amount of `s.tokenOut` received from the trade and swap.
    function tradeAndSwap(
        IPoolInternal.SwapArgs memory s,
        uint256 size,
        bool isBuy
    )
        external
        returns (
            uint256 totalPremium,
            Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        );

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
    ///         NOTE: This function can be called post or prior to expiration.
    /// @param size The size to annihilate
    function annihilate(uint256 size) external;

    /// @notice Exercises all long options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function exercise(address holder) external returns (uint256);

    /// @notice Settles all short options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    function settle(address holder) external returns (uint256);

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    function settlePosition(Position.Key memory p) external returns (uint256);

    /// @notice Get nearest ticks below `lower` and `upper`.
    ///         NOTE : If no tick between `lower` and `upper`, then the nearest tick below `upper`, will be `lower`
    /// @param lower The lower bound of the range
    /// @param upper The upper bound of the range
    /// @return nearestBelowLower The nearest tick below `lower`
    /// @return nearestBelowUpper The nearest tick below `upper`
    function getNearestTicksBelow(
        uint256 lower,
        uint256 upper
    )
        external
        view
        returns (uint256 nearestBelowLower, uint256 nearestBelowUpper);

    /// @notice Cancel given trade quotes
    /// @dev No check is done to ensure the given hash correspond to a quote provider by msg.sender,
    ///      but as we register the cancellation in a mapping provider -> hash, it is not possible to cancel a quote created by another provider
    /// @param hashes The hashes of the quotes to cancel
    function cancelTradeQuotes(bytes32[] calldata hashes) external;

    /// @notice Returns the size already filled for a given quote
    /// @param provider Provider of the quote
    /// @param tradeQuoteHash Hash of the quote
    function getTradeQuoteFilledAmount(
        address provider,
        bytes32 tradeQuoteHash
    ) external view returns (uint256);
}
