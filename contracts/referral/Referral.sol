// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {ZERO} from "../libraries/OptionMath.sol";

import {IPoolFactory} from "../factory/PoolFactory.sol";

import {IReferral} from "./IReferral.sol";
import {ReferralStorage} from "./ReferralStorage.sol";

contract Referral is IReferral, OwnableInternal {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using ReferralStorage for address;

    address internal immutable FACTORY;

    constructor(address factory) {
        FACTORY = factory;
    }

    /// @inheritdoc IReferral
    function getReferrer(address user) external view returns (address) {
        return ReferralStorage.layout().referrals[user];
    }

    /// @inheritdoc IReferral
    function getRebateTier(address referrer) public view returns (RebateTier) {
        return ReferralStorage.layout().rebateTiers[referrer];
    }

    /// @inheritdoc IReferral
    function getRebatePercents()
        external
        view
        returns (
            UD60x18[] memory primaryRebatePercents,
            UD60x18 secondaryRebatePercent
        )
    {
        ReferralStorage.Layout storage l = ReferralStorage.layout();
        primaryRebatePercents = l.primaryRebatePercents;
        secondaryRebatePercent = l.secondaryRebatePercent;
    }

    /// @inheritdoc IReferral
    function getRebatePercents(
        address referrer
    )
        public
        view
        returns (UD60x18 primaryRebatePercents, UD60x18 secondaryRebatePercent)
    {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        return (
            l.primaryRebatePercents[uint8(getRebateTier(referrer))],
            l.referrals[referrer] != address(0)
                ? l.secondaryRebatePercent
                : ZERO
        );
    }

    /// @inheritdoc IReferral
    function getRebates(
        address referrer
    ) public view returns (address[] memory, uint256[] memory) {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        address[] memory tokens = l.rebateTokens[referrer].toArray();
        uint256[] memory rebates = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            rebates[i] = l.rebates[referrer][tokens[i]];
        }

        return (tokens, rebates);
    }

    /// @inheritdoc IReferral
    function setRebateTier(
        address referrer,
        RebateTier tier
    ) external onlyOwner {
        ReferralStorage.Layout storage l = ReferralStorage.layout();
        emit SetRebateTier(referrer, l.rebateTiers[referrer], tier);
        l.rebateTiers[referrer] = tier;
    }

    /// @inheritdoc IReferral
    function setPrimaryRebatePercent(
        UD60x18 percent,
        RebateTier tier
    ) external onlyOwner {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        emit SetPrimaryRebatePercent(
            tier,
            l.primaryRebatePercents[uint8(tier)],
            percent
        );

        l.primaryRebatePercents[uint8(tier)] = percent;
    }

    /// @inheritdoc IReferral
    function setSecondaryRebatePercent(UD60x18 percent) external onlyOwner {
        ReferralStorage.Layout storage l = ReferralStorage.layout();
        emit SetSecondaryRebatePercent(l.secondaryRebatePercent, percent);
        l.secondaryRebatePercent = percent;
    }

    /// @inheritdoc IReferral
    function useReferral(
        address user,
        address primaryReferrer,
        address token,
        UD60x18 tradingFee
    ) external returns (UD60x18 totalRebate) {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        _revertIfPoolNotAuthorized();

        primaryReferrer = _trySetReferrer(user, primaryReferrer);
        if (primaryReferrer == address(0)) return ZERO;

        (
            UD60x18 primaryRebatePercent,
            UD60x18 secondaryRebatePercent
        ) = getRebatePercents(primaryReferrer);

        uint256 primaryRebate;
        uint256 secondaryRebate;

        {
            UD60x18 _primaryRebate = tradingFee * primaryRebatePercent;
            UD60x18 _secondaryRebate = tradingFee * secondaryRebatePercent;
            totalRebate = _primaryRebate + _secondaryRebate;

            primaryRebate = token.toTokenDecimals(_primaryRebate);
            secondaryRebate = token.toTokenDecimals(_secondaryRebate);
            uint256 _totalRebate = primaryRebate + secondaryRebate;

            IERC20(token).safeTransferFrom(
                msg.sender,
                address(this),
                _totalRebate
            );
        }

        address secondaryReferrer = l.referrals[primaryReferrer];

        if (secondaryRebate > 0) {
            l.rebates[secondaryReferrer][token] += secondaryRebate;

            if (!l.rebateTokens[secondaryReferrer].contains(token))
                l.rebateTokens[secondaryReferrer].add(token);
        }

        l.rebates[primaryReferrer][token] += primaryRebate;

        if (!l.rebateTokens[primaryReferrer].contains(token))
            l.rebateTokens[primaryReferrer].add(token);

        emit Refer(
            user,
            primaryReferrer,
            secondaryReferrer,
            token,
            primaryRebatePercent,
            totalRebate
        );
    }

    /// @inheritdoc IReferral
    function claimRebate() external {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        (address[] memory tokens, uint256[] memory rebates) = getRebates(
            msg.sender
        );

        if (tokens.length == 0) revert Referral__NoRebatesToClaim();

        for (uint256 i = 0; i < tokens.length; i++) {
            l.rebates[msg.sender][tokens[i]] = 0;
            l.rebateTokens[msg.sender].remove(tokens[i]);

            IERC20(tokens[i]).safeTransfer(msg.sender, rebates[i]);
            emit ClaimRebate(msg.sender, tokens[i], rebates[i]);
        }
    }

    /// @notice Sets the `referrer` for a `user` if they don't already have one. If a referrer has already been set, return the existing referrer.
    function _trySetReferrer(
        address user,
        address referrer
    ) internal returns (address) {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        if (l.referrals[user] == address(0)) {
            if (referrer == address(0)) return address(0);
            l.referrals[user] = referrer;
        } else {
            referrer = l.referrals[user];
        }

        return referrer;
    }

    /// @notice Reverts if the caller is not an authorized pool
    function _revertIfPoolNotAuthorized() internal view {
        if (!IPoolFactory(FACTORY).isPool(msg.sender))
            revert Referral__PoolNotAuthorized();
    }
}
