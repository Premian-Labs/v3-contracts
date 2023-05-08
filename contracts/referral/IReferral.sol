// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IReferral {
    enum RebateTier {
        PRIMARY_REBATE_1,
        PRIMARY_REBATE_2,
        PRIMARY_REBATE_3
    }

    error Referral__NoRebatesToClaim();
    error Referral__ReferrerAlreadySet(address referrer);

    event ClaimRebate(
        address indexed referrer,
        address indexed token,
        uint256 amount
    );

    event SetPrimaryRebatePercent(
        RebateTier tier,
        UD60x18 oldPercent,
        UD60x18 newPercent
    );

    event SetRebateTier(
        address indexed referrer,
        RebateTier oldTier,
        RebateTier newTier
    );

    event SetSecondaryRebatePercent(UD60x18 oldPercent, UD60x18 newPercent);

    event Referral(
        address indexed user,
        address indexed primaryReferrer,
        address indexed secondaryReferrer,
        address token,
        UD60x18 tier,
        UD60x18 totalRebate
    );

    /// @notice Returns the address of the referrer for a given user
    /// @param user The address of the user
    /// @return referrer The address of the referrer
    function getReferrer(address user) external view returns (address referrer);

    /// @notice Returns the rebate tier for a given referrer
    /// @param referrer The address of the referrer
    /// @return tier The rebate tier
    function getRebateTier(
        address referrer
    ) external view returns (RebateTier tier);

    /// @notice Returns the primary and secondary rebate percents
    /// @return primaryRebatePercents The primary rebate percents (18 decimals)
    /// @return secondaryRebatePercent The secondary rebate percent (18 decimals)
    function getRebatePercents()
        external
        view
        returns (
            UD60x18[] memory primaryRebatePercents,
            UD60x18 secondaryRebatePercent
        );

    /// @notice Returns the primary and secondary rebate percents for a given referrer
    /// @param referrer The address of the referrer
    /// @return primaryRebatePercent The primary rebate percent (18 decimals)
    /// @return secondaryRebatePercent The secondary rebate percent (18 decimals)
    function getRebatePercents(
        address referrer
    )
        external
        view
        returns (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent);

    /// @notice Returns the rebates for a given referrer
    /// @param referrer The address of the referrer
    /// @return tokens The tokens for which the referrer has rebates
    /// @return rebates The rebates for each token (token decimals)
    function getRebates(
        address referrer
    ) external view returns (address[] memory tokens, uint256[] memory rebates);

    /// @notice Sets the referrer for the msg.sender
    /// @param referrer The address of the referrer
    function setReferrer(address referrer) external;

    /// @notice Sets the rebate tier for a given referrer
    /// @param referrer The address of the referrer
    /// @param tier The rebate tier
    function setRebateTier(address referrer, RebateTier tier) external;

    /// @notice Sets the primary rebate percents
    /// @param percent The primary rebate percent (18 decimals)
    /// @param tier The rebate tier
    function setPrimaryRebatePercent(UD60x18 percent, RebateTier tier) external;

    /// @notice Sets the secondary rebate percent
    /// @param percent The secondary rebate percent (18 decimals)
    function setSecondaryRebatePercent(UD60x18 percent) external;

    /// @notice Calculate the primary and secondary rebate and pulls the tokens from msg.sender
    /// @dev The tokens must be approved for transfer
    /// @param user The address of the user
    /// @param primaryReferrer The address of the primary referrer
    /// @param token The address of the token
    /// @param tradingFee The trading fee (18 decimals)
    /// @return totalRebate The total rebate, sum of the primary and seconary rebates (18 decimals)
    function useReferral(
        address user,
        address primaryReferrer,
        address token,
        UD60x18 tradingFee
    ) external returns (UD60x18 totalRebate);

    /// @notice Claims the rebates for the msg.sender
    function claimRebate() external;
}
