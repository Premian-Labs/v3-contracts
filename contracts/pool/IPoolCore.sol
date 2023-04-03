// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";

interface IPoolCore is IPoolInternal {
    /// @notice Get the current market price as normalized price
    /// @return The current market price as normalized price
    function marketPrice() external view returns (UD60x18);

    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param size The size of a trade (number of contracts) | 18 decimals
    /// @param premium The total cost of option(s) for a purchase | poolToken decimals
    /// @param isPremiumNormalized Whether the premium given is already normalized by strike or not (Ex: For a strike of 1500, and a premium of 750, the normalized premium would be 0.5)
    /// @return The taker fee for an option trade denormalized | poolToken decimals
    function takerFee(
        UD60x18 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256);

    /// @notice Returns all pool parameters used for deployment
    /// @return base Address of base token
    /// @return quote Address of quote token
    /// @return oracleAdapter Address of oracle adapter
    /// @return strike The strike of the option | 18 decimals
    /// @return maturity The maturity timestamp of the option
    /// @return isCallPool Whether the pool is for call or put options
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address quote,
            address oracleAdapter,
            UD60x18 strike,
            uint64 maturity,
            bool isCallPool
        );

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    /// @param p The position key
    /// @return The amount of claimed fees | poolToken decimals
    function claim(Position.Key memory p) external returns (uint256);

    /// @notice Returns total claimable fees for the position
    /// @param p The position key
    /// @return The total claimable fees for the position | poolToken decimals
    function getClaimableFees(
        Position.Key memory p
    ) external view returns (uint256);

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
    /// @param size The position size to deposit | 18 decimals
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) | 18 decimals
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) | 18 decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return delta The net collateral / longs / shorts change
    function deposit(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data memory permit
    ) external returns (Position.Delta memory delta);

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
    /// @param size The position size to deposit | 18 decimals
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) | 18 decimals
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) | 18 decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)
    /// @return delta The net collateral / longs / shorts change
    function deposit(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data memory permit,
        bool isBidIfStrandedMarketPrice
    ) external returns (Position.Delta memory delta);

    /// @notice Swap tokens and deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param s The swap arguments
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
    /// @param size The position size to deposit | 18 decimals
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) | 18 decimals
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) | 18 decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return delta The net collateral / longs / shorts change
    function swapAndDeposit(
        IPoolInternal.SwapArgs memory s,
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data memory permit
    ) external payable returns (Position.Delta memory delta);

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param p The position key
    /// @param size The position size to withdraw | 18 decimals
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) | 18 decimals
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) | 18 decimals
    /// @return delta The net collateral / longs / shorts change
    function withdraw(
        Position.Key memory p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external returns (Position.Delta memory delta);

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    ///         Tx will revert if market price is not between `minMarketPrice` and `maxMarketPrice`.
    /// @param s The swap arguments
    /// @param p The position key
    /// @param size The position size to withdraw | 18 decimals
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert) | 18 decimals
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert) | 18 decimals
    /// @return delta The net collateral / longs / shorts change
    /// @return collateralReceived The amount of un-swapped collateral received from the trade. | s.tokenOut decimals
    /// @return tokenOutReceived The final amount of `s.tokenOut` received from the trade and swap. | poolToken decimals
    function withdrawAndSwap(
        SwapArgs memory s,
        Position.Key memory p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    )
        external
        returns (
            Position.Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        );

    /// @notice Underwrite an option by depositing collateral
    /// @param underwriter The underwriter of the option (Collateral will be taken from this address, and it will receive the short token)
    /// @param longReceiver The address which will receive the long token
    /// @param size The number of contracts being underwritten | 18 decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size,
        Permit2.Data memory permit
    ) external;

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
    ///         NOTE: This function can be called post or prior to expiration.
    /// @param size The size to annihilate | 18 decimals
    function annihilate(UD60x18 size) external;

    /// @notice Exercises all long options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    /// @return The exercise value as amount of collateral paid out | poolToken decimals
    function exercise(address holder) external returns (uint256);

    /// @notice Settles all short options held by an `owner`, ignoring automatic settlement fees.
    /// @param holder The holder of the contracts
    /// @return The amount of collateral left after settlement | poolToken decimals
    function settle(address holder) external returns (uint256);

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    /// @return The amount of collateral left after settlement | poolToken decimals
    function settlePosition(Position.Key memory p) external returns (uint256);

    /// @notice Get nearest ticks below `lower` and `upper`.
    ///         NOTE : If no tick between `lower` and `upper`, then the nearest tick below `upper`, will be `lower`
    /// @param lower The lower bound of the range | 18 decimals
    /// @param upper The upper bound of the range | 18 decimals
    /// @return nearestBelowLower The nearest tick below `lower` | 18 decimals
    /// @return nearestBelowUpper The nearest tick below `upper` | 18 decimals
    function getNearestTicksBelow(
        UD60x18 lower,
        UD60x18 upper
    )
        external
        view
        returns (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper);

    /// @notice Transfer a LP position to a new owner/operator
    /// @param srcP The position key
    /// @param newOwner The new owner
    /// @param newOperator The new operator
    /// @param size The size to transfer | 18 decimals
    function transferPosition(
        Position.Key memory srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) external;
}
