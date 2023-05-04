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
        UD60x18 rebate
    );

    function getReferrer(address user) external view returns (address);

    function getRebateTier(address referrer) external view returns (RebateTier);

    function getRebatePercents()
        external
        view
        returns (UD60x18[] memory, UD60x18);

    function getRebateTierPercent(
        address referrer
    ) external view returns (UD60x18);

    function getRebates(
        address referrer
    ) external view returns (address[] memory, uint256[] memory);

    function setReferrer(address referrer) external;

    function setRebateTier(address referrer, RebateTier tier) external;

    function setPrimaryRebatePercent(UD60x18 percent, RebateTier tier) external;

    function setSecondaryRebatePercent(UD60x18 percent) external;

    function useReferral(
        address user,
        address primaryReferrer,
        address token,
        UD60x18 tradingFee
    ) external returns (UD60x18 rebate);

    function claimRebate() external;
}
