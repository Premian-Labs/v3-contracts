// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

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
    /// @return The taker fee for an option trade denormalized (poolToken decimals)
    function takerFee(
        address taker,
        UD60x18 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256);

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
        returns (
            address base,
            address quote,
            address oracleAdapter,
            UD60x18 strike,
            uint256 maturity,
            bool isCallPool
        );

    /// @notice Returns the IPoolInternal.Tick with the liquidity rate at that price
    /// @param  price The normalized option price of the tick (18 decimals)
    /// @return The tick at the price, with the liquidityNet (18 decimals) of the tick
    function tick(
        UD60x18 price
    ) external view returns (IPoolInternal.TickWithLiquidity memory);

    /// @notice Returns all ticks in the pool, including net liquidity for each tick
    /// @return ticks All pool ticks with the liquidityNet (18 decimals) of each tick
    function ticks()
        external
        view
        returns (IPoolInternal.TickWithLiquidity[] memory);

    /// @notice Returns the net liquidity for a given tick, to the next tick in the range
    /// @param  price The normalized option price of the tick (18 decimals)
    /// @return liquidityNet The net liquidity of the tick (18 decimals)
    function liquidityForTick(
        UD60x18 price
    ) external view returns (UD60x18 liquidityNet);

    /// @notice Returns the net liquidity for a given range of ticks
    /// @param  lower The normalized option price of the lower tick (18 decimals)
    /// @param  upper The normalized option price of the upper tick (18 decimals)
    /// @param  liquidityRate The liquidity rate at the tick range (18 decimals)
    /// @return liquidityNet The net liquidity for the range (18 decimals)
    function liquidityForRange(
        UD60x18 lower,
        UD60x18 upper,
        UD60x18 liquidityRate
    ) external view returns (UD60x18 liquidityNet);

    /// @notice Updates the claimable fees of a position and transfers the claimed
    ///         fees to the operator of the position. Then resets the claimable fees to
    ///         zero.
    /// @param p The position key
    /// @return The amount of claimed fees (poolToken decimals)
    function claim(Position.Key calldata p) external returns (uint256);

    /// @notice Returns total claimable fees for the position
    /// @param p The position key
    /// @return The total claimable fees for the position (poolToken decimals)
    function getClaimableFees(
        Position.Key calldata p
    ) external view returns (uint256);

    /// @notice Underwrite an option by depositing collateral
    /// @param underwriter The underwriter of the option (Collateral will be taken from this address, and it will receive the short token)
    /// @param longReceiver The address which will receive the long token
    /// @param size The number of contracts being underwritten (18 decimals)
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size
    ) external;

    /// @notice Annihilate a pair of long + short option contracts to unlock the stored collateral.
    ///         NOTE: This function can be called post or prior to expiration.
    /// @param size The size to annihilate (18 decimals)
    function annihilate(UD60x18 size) external;

    /// @notice Exercises all long options held by caller
    /// @return The exercise value as amount of collateral paid out (poolToken decimals)
    function exercise() external returns (uint256);

    /// @notice Batch exercises all long options held by each `holder`, caller is reimbursed with the cost deducted from the proceeds of the
    ///         exercised options. Only authorized agents may execute this function on behalf of the option holder.
    /// @param holders The holders of the contracts
    /// @param costPerHolder The cost charged by the authorized agent, per option holder (poolToken decimals)
    /// @return The exercise value as amount of collateral paid out per holder, ignoring costs applied during automatic exercise (poolToken decimals)
    function exerciseFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external returns (uint256[] memory);

    /// @notice Settles all short options held by caller
    /// @return The amount of collateral left after settlement (poolToken decimals)
    function settle() external returns (uint256);

    /// @notice Batch settles all short options held by each `holder`, caller is reimbursed with the cost deducted from the proceeds of the
    ///         settled options. Only authorized agents may execute this function on behalf of the option holder.
    /// @param holders The holders of the contracts
    /// @param costPerHolder The cost charged by the authorized agent, per option holder (poolToken decimals)
    /// @return The amount of collateral left after settlement per holder, ignoring costs applied during automatic settlement (poolToken decimals)
    function settleFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external returns (uint256[] memory);

    /// @notice Reconciles a user's `position` to account for settlement payouts post-expiration.
    /// @param p The position key
    /// @return The amount of collateral left after settlement (poolToken decimals)
    function settlePosition(Position.Key calldata p) external returns (uint256);

    /// @notice Batch reconciles each `position` to account for settlement payouts post-expiration. Caller is reimbursed with the cost deducted
    ///         from the proceeds of the settled position. Only authorized agents may execute this function on behalf of the option holder.
    /// @param p The position keys
    /// @param costPerHolder The cost charged by the authorized agent, per position holder (poolToken decimals)
    /// @return The amount of collateral left after settlement per holder, ignoring costs applied during automatic settlement (poolToken decimals)
    function settlePositionFor(
        Position.Key[] calldata p,
        uint256 costPerHolder
    ) external returns (uint256[] memory);

    /// @notice Transfer a LP position to a new owner/operator
    /// @param srcP The position key
    /// @param newOwner The new owner
    /// @param newOperator The new operator
    /// @param size The size to transfer (18 decimals)
    function transferPosition(
        Position.Key calldata srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) external;
}
