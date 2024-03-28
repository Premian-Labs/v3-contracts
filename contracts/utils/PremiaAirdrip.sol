// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {ONE} from "../libraries/Constants.sol";
import {IPremiaAirdrip} from "./IPremiaAirdrip.sol";
import {PremiaAirdripStorage} from "./PremiaAirdripStorage.sol";

contract PremiaAirdrip is IPremiaAirdrip, OwnableInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice premia token interface
    IERC20 public immutable PREMIA;
    /// @notice total allocation of premia distributed over the vesting period
    UD60x18 public constant TOTAL_ALLOCATION = UD60x18.wrap(2_000_000e18);
    /// @notice total allocation of premia distributed over the vesting period
    UD60x18 public constant VESTING_INTERVALS = UD60x18.wrap(12e18);

    constructor(IERC20 premia) {
        PREMIA = premia;
    }

    /// @inheritdoc IPremiaAirdrip
    function initialize(User[] memory users) external nonReentrant onlyOwner {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        if (l.initialized) revert PremiaAirdrip__Initialized();
        if (users.length == 0) revert PremiaAirdrip__ArrayEmpty();

        PREMIA.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOCATION.unwrap());

        l.vestingDates = [
            1723708800, // Thu Aug 15 2024 08:00:00 GMT+0000
            1726387200, // Sun Sep 15 2024 08:00:00 GMT+0000
            1728979200, // Tue Oct 15 2024 08:00:00 GMT+0000
            1731657600, // Fri Nov 15 2024 08:00:00 GMT+0000
            1734249600, // Sun Dec 15 2024 08:00:00 GMT+0000
            1736928000, // Wed Jan 15 2025 08:00:00 GMT+0000
            1739606400, // Sat Feb 15 2025 08:00:00 GMT+0000
            1742025600, // Sat Mar 15 2025 08:00:00 GMT+0000
            1744704000, // Tue Apr 15 2025 08:00:00 GMT+0000
            1747296000, // Thu May 15 2025 08:00:00 GMT+0000
            1749974400, // Sun Jun 15 2025 08:00:00 GMT+0000
            1752566400 // Tue Jul 15 2025 08:00:00 GMT+0000
        ];

        UD60x18 totalInfluence;
        for (uint256 i = 0; i < users.length; i++) {
            User memory u = users[i];
            if (u.user == address(0) || u.influence < ONE) revert PremiaAirdrip__InvalidUser(u.user, u.influence);
            l.influence[u.user] = u.influence;
            totalInfluence = totalInfluence + u.influence;
        }

        l.emissionRate = (TOTAL_ALLOCATION / totalInfluence) / VESTING_INTERVALS;
        emit Initialized(l.emissionRate, totalInfluence);

        l.initialized = true;
    }

    /// @inheritdoc IPremiaAirdrip
    function claim() external nonReentrant {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        if (!l.initialized) revert PremiaAirdrip__NotInitialized();

        uint256 amount;
        uint256 allocation = _calculateAllocation(l, msg.sender);
        for (uint256 i = 0; i < l.vestingDates.length; i++) {
            uint256 vestingDate = l.vestingDates[i];

            if (vestingDate > block.timestamp) continue;
            if (l.allocations[msg.sender][vestingDate] > 0) continue;

            amount = amount + allocation;
            l.allocations[msg.sender][vestingDate] = allocation;
        }

        if (amount == 0) revert PremiaAirdrip__ZeroAmountClaimable();

        PREMIA.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount, allocation);
    }

    function _calculateAllocation(PremiaAirdripStorage.Layout storage l, address user) internal view returns (uint256) {
        return (l.influence[user] * l.emissionRate).unwrap();
    }

    /// @inheritdoc IPremiaAirdrip
    function previewVestingSchedule(address user) external view returns (Allocation[12] memory allocations) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        for (uint256 i = 0; i < l.vestingDates.length; i++) {
            allocations[i] = Allocation({amount: _calculateAllocation(l, user), vestDate: l.vestingDates[i]});
        }
        return allocations;
    }

    /// @inheritdoc IPremiaAirdrip
    function previewClaimedAllocations(address user) external view returns (Allocation[12] memory allocations) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        for (uint256 i = 0; i < l.vestingDates.length; i++) {
            uint256 vestingDate = l.vestingDates[i];
            allocations[i] = Allocation({amount: l.allocations[user][vestingDate], vestDate: vestingDate});
        }
        return allocations;
    }

    /// @inheritdoc IPremiaAirdrip
    function previewPendingAllocations(address user) external view returns (Allocation[12] memory allocations) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        for (uint256 i = 0; i < l.vestingDates.length; i++) {
            uint256 vestingDate = l.vestingDates[i];
            uint256 allocation = l.allocations[user][vestingDate] > 0 ? 0 : _calculateAllocation(l, user);
            allocations[i] = Allocation({amount: allocation, vestDate: vestingDate});
        }
        return allocations;
    }
}
