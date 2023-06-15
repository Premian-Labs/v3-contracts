// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IReferral {
    enum RebateTier {
        PrimaryRebate1,
        PrimaryRebate2,
        PrimaryRebate3
    }

    error Referral__NoRebatesToClaim();
    error Referral__PoolNotAuthorized();

    event ClaimRebate(address indexed referrer, address indexed token, uint256 amount);

    event SetPrimaryRebatePercent(RebateTier tier, UD60x18 oldPercent, UD60x18 newPercent);

    event SetRebateTier(address indexed referrer, RebateTier oldTier, RebateTier newTier);

    event SetSecondaryRebatePercent(UD60x18 oldPercent, UD60x18 newPercent);

    event Refer(
        address indexed user,
        address indexed primaryReferrer,
        address indexed secondaryReferrer,
        address token,
        UD60x18 tier,
        UD60x18 primaryRebate,
        UD60x18 secondaryRebate
    );

    /// @notice Returns the address of the referrer for a given user
    /// @param user The address of the user
    /// @return referrer The address of the referrer
    function getReferrer(address user) external view returns (address referrer);

    /// @notice Returns the rebate tier for a given referrer
    /// @param referrer The address of the referrer
    /// @return tier The rebate tier
    function getRebateTier(address referrer) external view returns (RebateTier tier);

    /// @notice Returns the primary and secondary rebate percents
    /// @return primaryRebatePercents The primary rebate percents (18 decimals)
    /// @return secondaryRebatePercent The secondary rebate percent (18 decimals)
    function getRebatePercents()
        external
        view
        returns (UD60x18[] memory primaryRebatePercents, UD60x18 secondaryRebatePercent);

    /// @notice Returns the primary and secondary rebate percents for a given referrer
    /// @param referrer The address of the referrer
    /// @return primaryRebatePercent The primary rebate percent (18 decimals)
    /// @return secondaryRebatePercent The secondary rebate percent (18 decimals)
    function getRebatePercents(
        address referrer
    ) external view returns (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent);

    /// @notice Returns the rebates for a given referrer
    /// @param referrer The address of the referrer
    /// @return tokens The tokens for which the referrer has rebates
    /// @return rebates The rebates for each token (token decimals)
    function getRebates(address referrer) external view returns (address[] memory tokens, uint256[] memory rebates);

    /// @notice Returns the primary and secondary rebate amounts for a given `user` and `referrer`
    /// @param user The address of the user
    /// @param referrer The address of the referrer
    /// @param tradingFee The trading fee (18 decimals)
    /// @return primaryRebate The primary rebate amount (18 decimals)
    /// @return secondaryRebate The secondary rebate amount (18 decimals)
    function getRebateAmounts(
        address user,
        address referrer,
        UD60x18 tradingFee
    ) external view returns (UD60x18 primaryRebate, UD60x18 secondaryRebate);

    /// @notice Sets the rebate tier for a given referrer - caller must be owner
    /// @param referrer The address of the referrer
    /// @param tier The rebate tier
    function setRebateTier(address referrer, RebateTier tier) external;

    /// @notice Sets the primary rebate percents - caller must be owner
    /// @param percent The primary rebate percent (18 decimals)
    /// @param tier The rebate tier
    function setPrimaryRebatePercent(UD60x18 percent, RebateTier tier) external;

    /// @notice Sets the secondary rebate percent - caller must be owner
    /// @param percent The secondary rebate percent (18 decimals)
    function setSecondaryRebatePercent(UD60x18 percent) external;

    /// @notice Pulls the total rebate amount from msg.sender - caller must be an authorized pool
    /// @dev The tokens must be approved for transfer
    /// @param user The address of the user
    /// @param referrer The address of the primary referrer
    /// @param token The address of the token
    /// @param primaryRebate The primary rebate amount (18 decimals)
    /// @param secondaryRebate The secondary rebate amount (18 decimals)
    function useReferral(
        address user,
        address referrer,
        address token,
        UD60x18 primaryRebate,
        UD60x18 secondaryRebate
    ) external;

    /// @notice Claims the rebates for the msg.sender
    function claimRebate() external;
}
