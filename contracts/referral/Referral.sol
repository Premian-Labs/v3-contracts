// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {ZERO} from "../libraries/OptionMath.sol";

import {IPoolFactory} from "../factory/PoolFactory.sol";

import {IReferral} from "./IReferral.sol";
import {ReferralStorage} from "./ReferralStorage.sol";

contract Referral is IReferral, OwnableInternal, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using ReferralStorage for address;

    address internal immutable FACTORY;

    constructor(address factory) {
        FACTORY = factory;
    }

    /// @inheritdoc IReferral
    function getReferrer(address user) public view returns (address) {
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
        returns (UD60x18[] memory primaryRebatePercents, UD60x18 secondaryRebatePercent)
    {
        ReferralStorage.Layout storage l = ReferralStorage.layout();
        primaryRebatePercents = l.primaryRebatePercents;
        secondaryRebatePercent = l.secondaryRebatePercent;
    }

    /// @inheritdoc IReferral
    function getRebatePercents(
        address referrer
    ) public view returns (UD60x18 primaryRebatePercents, UD60x18 secondaryRebatePercent) {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        return (
            l.primaryRebatePercents[uint8(getRebateTier(referrer))],
            l.referrals[referrer] != address(0) ? l.secondaryRebatePercent : ZERO
        );
    }

    /// @inheritdoc IReferral
    function getRebates(address referrer) public view returns (address[] memory, uint256[] memory) {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        address[] memory tokens = l.rebateTokens[referrer].toArray();
        uint256[] memory rebates = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            rebates[i] = l.rebates[referrer][tokens[i]];
        }

        return (tokens, rebates);
    }

    /// @inheritdoc IReferral
    function getRebateAmounts(
        address user,
        address referrer,
        UD60x18 tradingFee
    ) external view returns (UD60x18 primaryRebate, UD60x18 secondaryRebate) {
        if (referrer == address(0)) referrer = getReferrer(user);
        if (referrer == address(0)) return (ZERO, ZERO);

        (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = getRebatePercents(referrer);
        primaryRebate = tradingFee * primaryRebatePercent;
        secondaryRebate = primaryRebate * secondaryRebatePercent;
    }

    /// @inheritdoc IReferral
    function setRebateTier(address referrer, RebateTier tier) external onlyOwner {
        ReferralStorage.Layout storage l = ReferralStorage.layout();
        emit SetRebateTier(referrer, l.rebateTiers[referrer], tier);
        l.rebateTiers[referrer] = tier;
    }

    /// @inheritdoc IReferral
    function setPrimaryRebatePercent(UD60x18 percent, RebateTier tier) external onlyOwner {
        ReferralStorage.Layout storage l = ReferralStorage.layout();
        emit SetPrimaryRebatePercent(tier, l.primaryRebatePercents[uint8(tier)], percent);
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
        address referrer,
        address token,
        UD60x18 primaryRebate,
        UD60x18 secondaryRebate
    ) external nonReentrant {
        _revertIfPoolNotAuthorized();

        referrer = _trySetReferrer(user, referrer);
        if (referrer == address(0)) return;

        UD60x18 totalRebate = primaryRebate + secondaryRebate;
        if (totalRebate == ZERO) return;

        IERC20(token).safeTransferFrom(msg.sender, address(this), token.toTokenDecimals(totalRebate));

        ReferralStorage.Layout storage l = ReferralStorage.layout();
        address secondaryReferrer = l.referrals[referrer];
        _tryUpdateRebate(l, secondaryReferrer, token, secondaryRebate);
        _tryUpdateRebate(l, referrer, token, primaryRebate);

        (UD60x18 primaryRebatePercent, ) = getRebatePercents(referrer);
        emit Refer(user, referrer, secondaryReferrer, token, primaryRebatePercent, primaryRebate, secondaryRebate);
    }

    /// @inheritdoc IReferral
    function claimRebate(address[] memory tokens) external nonReentrant {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 rebate = l.rebates[msg.sender][tokens[i]];
            if (rebate == 0) continue;

            l.rebates[msg.sender][tokens[i]] = 0;
            l.rebateTokens[msg.sender].remove(tokens[i]);

            IERC20(tokens[i]).safeTransfer(msg.sender, rebate);
            emit ClaimRebate(msg.sender, tokens[i], rebate);
        }
    }

    /// @notice Updates the `referrer` rebate balance and rebate tokens, if `amount` is greater than zero
    function _tryUpdateRebate(
        ReferralStorage.Layout storage l,
        address referrer,
        address token,
        UD60x18 amount
    ) internal {
        if (amount > ZERO) {
            l.rebates[referrer][token] += token.toTokenDecimals(amount);
            if (!l.rebateTokens[referrer].contains(token)) l.rebateTokens[referrer].add(token);
        }
    }

    /// @notice Sets the `referrer` for a `user` if they don't already have one. If a referrer has already been set,
    ///         return the existing referrer.
    function _trySetReferrer(address user, address referrer) internal returns (address) {
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
        if (!IPoolFactory(FACTORY).isPool(msg.sender)) revert Referral__PoolNotAuthorized();
    }
}
