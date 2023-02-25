// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolInternal} from "./IPoolInternal.sol";
import {Position} from "../libraries/Position.sol";

interface IPoolCore is IPoolInternal {
    /// @notice Get the current market price as normalized price
    /// @return The current market price as normalized price
    function marketPrice() external view returns (uint256);

    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param size The size of a trade (number of contracts)
    /// @param premium The total cost of option(s) for a purchase
    /// @param isPremiumNormalized Whether the premium given is already normalized by strike or not (Ex: For a strike of 1500, and a premium of 750, the normalized premium would be 0.5)
    /// @return The taker fee for an option trade denormalized
    function takerFee(
        uint256 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256);

    /// @notice Returns all pool parameters used for deployment
    /// @return base Address of base token
    /// @return quote Address of quote token
    /// @return oracleAdapter Address of oracle adapter
    /// @return strike The strike of the option
    /// @return maturity The maturity timestamp of the option
    /// @return isCallPool Whether the pool is for call or put options
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address quote,
            address oracleAdapter,
            uint256 strike,
            uint64 maturity,
            bool isCallPool
        );

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
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert)
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 minMarketPrice,
        uint256 maxMarketPrice
    ) external;

    /// @notice Deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert)
    /// @param isBidIfStrandedMarketPrice Whether this is a bid or ask order when the market price is stranded (This argument doesnt matter if market price is not stranded)
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 minMarketPrice,
        uint256 maxMarketPrice,
        bool isBidIfStrandedMarketPrice
    ) external;

    /// @notice Swap tokens and deposits a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) into the pool.
    /// @param s The swap arguments
    /// @param p The position key
    /// @param belowLower The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param belowUpper The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas
    /// @param size The position size to deposit
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert)
    function swapAndDeposit(
        IPoolInternal.SwapArgs memory s,
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 minMarketPrice,
        uint256 maxMarketPrice
    ) external payable;

    /// @notice Withdraws a `position` (combination of owner/operator, price range, bid/ask collateral, and long/short contracts) from the pool
    /// @param p The position key
    /// @param size The position size to withdraw
    /// @param minMarketPrice Min market price, as normalized value. (If below, tx will revert)
    /// @param maxMarketPrice Max market price, as normalized value. (If above, tx will revert)
    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 minMarketPrice,
        uint256 maxMarketPrice
    ) external;

    /// @notice Underwrite an option by depositing collateral
    /// @param underwriter The underwriter of the option (Collateral will be taken from this address, and it will receive the short token)
    /// @param longReceiver The address which will receive the long token
    /// @param size The number of contracts being underwritten
    function writeFrom(
        address underwriter,
        address longReceiver,
        uint256 size
    ) external;

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
}
