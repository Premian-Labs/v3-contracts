// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

import {Position} from "../libraries/Position.sol";

interface IPoolCore is IPoolInternal {
    /// @notice Get the current market price as normalized price
    /// @return The current market price as normalized price
    function marketPrice() external view returns (UD60x18);

    /// @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
    /// @param taker The taker of a trade
    /// @param size The size of a trade (number of contracts) (18 decimals)
    /// @param premium The total cost of option(s) for a purchase (poolToken decimals)
    /// @param isPremiumNormalized Whether the premium given is already normalized by strike or not (Ex: For a strike of 1500, and a premium of 750, the normalized premium would be 0.5)
    /// @param isOrderbook Whether the fee is for the `fillQuoteOB` function or not
    /// @return The taker fee for an option trade denormalized (poolToken decimals)
    function takerFee(
        address taker,
        UD60x18 size,
        uint256 premium,
        bool isPremiumNormalized,
        bool isOrderbook
    ) external view returns (uint256);

    /// @notice Calculates the fee for a trade based on the `size` and `premiumNormalized` of the trade.
    /// @dev WARNING: It is recommended to use `takerFee` instead of this function. This function is a lower level
    ///      function here to be used when a pool has not yet be deployed, by calling it from the diamond contract
    ///      directly rather than a pool proxy. If using it from the pool, you should pass the same value as the pool
    ///      for `strike` and `isCallPool` in order to get the accurate takerFee
    /// @param taker The taker of a trade
    /// @param size The size of a trade (number of contracts) (18 decimals)
    /// @param premium The total cost of option(s) for a purchase (18 decimals)
    /// @param isPremiumNormalized Whether the premium given is already normalized by strike or not (Ex: For a strike of
    ///        1500, and a premium of 750, the normalized premium would be 0.5)
    /// @param isOrderbook Whether the fee is for the `fillQuoteOB` function or not
    /// @param strike The strike of the option (18 decimals)
    /// @param isCallPool Whether the pool is a call pool or not
    /// @return The taker fee for an option trade denormalized. (18 decimals)
    function _takerFeeLowLevel(
        address taker,
        UD60x18 size,
        UD60x18 premium,
        bool isPremiumNormalized,
        bool isOrderbook,
        UD60x18 strike,
        bool isCallPool
    ) external view returns (UD60x18);

    /// @notice Returns all pool parameters used for deployment
    /// @return base Address of base token
    /// @return quote Address of quote token
    /// @return oracleAdapter Address of oracle adapter
    /// @return strike The strike of the option (18 decimals)
    /// @return maturity The maturity timestamp of the option
    /// @return isCallPool Whether the pool is for call or put options
    function getPoolSettings()
        external
        view
        returns (address base, address quote, address oracleAdapter, UD60x18 strike, uint256 maturity, bool isCallPool);

    /// @notice Returns all ticks in the pool, including net liquidity for each tick
    /// @return ticks All pool ticks with the liquidityNet (18 decimals) of each tick
    function ticks() external view returns (IPoolInternal.TickWithRates[] memory);

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    /// @param p The position key
    /// @return The amount of claimed fees (poolToken decimals)
    function claim(Position.Key calldata p) external returns (uint256);

    /// @notice Returns total claimable fees for the position
    /// @param p The position key
    /// @return The total claimable fees for the position (poolToken decimals)
    function getClaimableFees(Position.Key calldata p) external view returns (uint256);

    /// @notice Underwrite an option by depositing collateral. By default the taker fee and referral are applied to the
    ///         underwriter, if the caller is a registered vault the longReceiver is used instead.
    /// @param underwriter The underwriter of the option (Collateral will be taken from this address, and it will
    ///        receive the short token)
    /// @param longReceiver The address which will receive the long token
    /// @param size The number of contracts being underwritten (18 decimals)
    /// @param referrer The referrer of the user doing the trade
    function writeFrom(address underwriter, address longReceiver, UD60x18 size, address referrer) external;

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
    /// @dev This function can be called post or prior to expiration.
    /// @param size The size to annihilate (18 decimals)
    function annihilate(UD60x18 size) external;

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral on behalf of another account.
    ///         msg.sender must be approved through `UserSettings.setAuthorizedAddress` by the owner of the long/short contracts.
    /// @dev This function can be called post or prior to expiration.
    /// @param owner The owner of the shorts/longs to annihilate
    /// @param size The size to annihilate (18 decimals)
    function annihilateFor(address owner, UD60x18 size) external;

    /// @notice Exercises all long options held by caller
    /// @return exerciseValue The exercise value as amount of collateral paid out to long holder (poolToken decimals)
    /// @return exerciseFee The fee paid to protocol (poolToken decimals)
    function exercise() external returns (uint256 exerciseValue, uint256 exerciseFee);

    /// @notice Batch exercises all long options held by each `holder`, caller is reimbursed with the cost deducted from
    ///         the proceeds of the exercised options. Only authorized agents may execute this function on behalf of the
    ///         option holder.
    /// @param holders The holders of the contracts
    /// @param costPerHolder The cost charged by the authorized operator, per option holder (poolToken decimals)
    /// @return exerciseValues The exercise value as amount of collateral paid out per holder, ignoring costs applied during automatic
    ///         exercise, but excluding protocol fees from amount (poolToken decimals)
    /// @return exerciseFees The fees paid to protocol (poolToken decimals)
    function exerciseFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external returns (uint256[] memory exerciseValues, uint256[] memory exerciseFees);

    /// @notice Settles all short options held by caller
    /// @return collateral The amount of collateral left after settlement (poolToken decimals)
    function settle() external returns (uint256 collateral);

    /// @notice Batch settles all short options held by each `holder`, caller is reimbursed with the cost deducted from
    ///         the proceeds of the settled options. Only authorized operators may execute this function on behalf of the
    ///         option holder.
    /// @param holders The holders of the contracts
    /// @param costPerHolder The cost charged by the authorized operator, per option holder (poolToken decimals)
    /// @return The amount of collateral left after settlement per holder, ignoring costs applied during automatic
    ///         settlement (poolToken decimals)
    function settleFor(address[] calldata holders, uint256 costPerHolder) external returns (uint256[] memory);

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    /// @return collateral The amount of collateral left after settlement (poolToken decimals)
    function settlePosition(Position.Key calldata p) external returns (uint256 collateral);

    /// @notice Batch reconciles each `position` to account for settlement payouts post-expiration. Caller is reimbursed
    ///         with the cost deducted from the proceeds of the settled position. Only authorized operators may execute
    ///         this function on behalf of the option holder.
    /// @param p The position keys
    /// @param costPerHolder The cost charged by the authorized operator, per position holder (poolToken decimals)
    /// @return The amount of collateral left after settlement per holder, ignoring costs applied during automatic
    ///         settlement (poolToken decimals)
    function settlePositionFor(Position.Key[] calldata p, uint256 costPerHolder) external returns (uint256[] memory);

    /// @notice Transfer a LP position to a new owner/operator
    /// @param srcP The position key
    /// @param newOwner The new owner
    /// @param newOperator The new operator
    /// @param size The size to transfer (18 decimals)
    function transferPosition(Position.Key calldata srcP, address newOwner, address newOperator, UD60x18 size) external;

    /// @notice Attempts to cache the settlement price of the option after expiration. Reverts if a price has already been cached
    function tryCacheSettlementPrice() external;

    /// @notice Returns the settlement price of the option.
    /// @return The settlement price of the option (18 decimals). Returns 0 if option is not settled yet.
    function getSettlementPrice() external view returns (UD60x18);

    /// @notice Gets the lower and upper bound of the stranded market area when it exists. In case the stranded market
    ///         area does not exist it will return the stranded market area the maximum tick price for both the lower
    ///         and the upper, in which case the market price is not stranded given any range order info order.
    /// @return lower Lower bound of the stranded market price area (Default : PoolStorage.MAX_TICK_PRICE + ONE = 2e18) (18 decimals)
    /// @return upper Upper bound of the stranded market price area (Default : PoolStorage.MAX_TICK_PRICE + ONE = 2e18) (18 decimals)
    function getStrandedArea() external view returns (UD60x18 lower, UD60x18 upper);

    /// @notice Returns the list of existing tokenIds with non zero balance
    /// @return tokenIds The list of existing tokenIds
    function getTokenIds() external view returns (uint256[] memory);
}
