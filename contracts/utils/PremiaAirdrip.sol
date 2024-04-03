// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {ZERO, ONE} from "../libraries/Constants.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";
import {UD50x28, ud50x28} from "../libraries/UD50x28.sol";

import {IPremiaAirdrip} from "./IPremiaAirdrip.sol";
import {PremiaAirdripStorage} from "./PremiaAirdripStorage.sol";

contract PremiaAirdrip is IPremiaAirdrip, OwnableInternal, ReentrancyGuard {
    using PRBMathExtra for UD60x18;
    using SafeERC20 for IERC20;

    /// @notice premia token interface
    IERC20 public constant PREMIA = IERC20(0x51fC0f6660482Ea73330E414eFd7808811a57Fa2);
    /// @notice total allocation of premia distributed over the vesting period
    UD60x18 public constant TOTAL_ALLOCATION = UD60x18.wrap(2_000_000e18);
    /// @notice duration of time premia is distributed
    uint256 public constant VESTING_DURATION = 365 days;
    // @notice date which the premia airdrip will start to vest
    uint256 public constant VESTING_START = 1723708800; // Thu Aug 15 2024 08:00:00 GMT+0000

    /// @inheritdoc IPremiaAirdrip
    function initialize(User[] memory users) external nonReentrant onlyOwner {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        if (l.initialized) revert PremiaAirdrip__Initialized();
        if (users.length == 0) revert PremiaAirdrip__ArrayEmpty();

        PREMIA.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOCATION.unwrap());

        UD60x18 totalInfluence;
        for (uint256 i = 0; i < users.length; i++) {
            User memory user = users[i];

            if (user.addr == address(0) || user.influence < ONE) {
                revert PremiaAirdrip__InvalidUser(user.addr, user.influence);
            }

            if (l.influence[user.addr] != ZERO) {
                revert PremiaAirdrip__UserAlreadyExists(user.addr);
            }

            l.influence[user.addr] = user.influence;
            totalInfluence = totalInfluence + user.influence;
        }

        l.premiaPerInfluence = TOTAL_ALLOCATION / totalInfluence;
        emit Initialized(l.premiaPerInfluence, totalInfluence);

        l.initialized = true;
    }

    /// @inheritdoc IPremiaAirdrip
    function claim() external nonReentrant {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();

        uint256 lastClaim = l.lastClaim[msg.sender];
        if (lastClaim >= block.timestamp) revert PremiaAirdrip__NotClaimable(lastClaim, block.timestamp);
        if (VESTING_START > block.timestamp) revert PremiaAirdrip__NotVested(VESTING_START, block.timestamp);
        if (!l.initialized) revert PremiaAirdrip__NotInitialized();

        uint256 amount = _calculateClaimAmount(l, msg.sender, lastClaim);
        if (amount == 0) revert PremiaAirdrip__ZeroAmountClaimable();

        l.lastClaim[msg.sender] = block.timestamp;
        l.claimed[msg.sender] += amount;

        PREMIA.safeTransfer(msg.sender, amount);

        uint256 claimed = l.claimed[msg.sender];
        uint256 remaining = _previewClaimRemaining(l, msg.sender);

        emit Claimed(msg.sender, amount, claimed, remaining);
    }

    function _calculateClaimAmount(
        PremiaAirdripStorage.Layout storage l,
        address user,
        uint256 lastClaim
    ) internal view returns (uint256) {
        uint256 vestingEnd = VESTING_START + VESTING_DURATION;
        uint256 endTimestamp = block.timestamp >= vestingEnd ? vestingEnd : block.timestamp;
        uint256 startTimestamp = lastClaim == 0 ? VESTING_START : lastClaim;

        if (startTimestamp >= endTimestamp) return 0;

        UD50x28 claimablePercent = ud50x28((endTimestamp - startTimestamp) * 1e28) / ud50x28(VESTING_DURATION * 1e28);
        UD50x28 totalAllocation = _previewTotalAllocationAmount(l, user).intoUD50x28();

        return (claimablePercent * totalAllocation).intoUD60x18().unwrap();
    }

    /// @inheritdoc IPremiaAirdrip
    function previewTotalAllocationAmount(address user) external view returns (uint256) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        return _previewTotalAllocationAmount(l, user).unwrap();
    }

    /// @inheritdoc IPremiaAirdrip
    function previewClaimableAmount(address user) external view returns (uint256) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        if (VESTING_START > block.timestamp) return 0;
        return _calculateClaimAmount(l, user, l.lastClaim[user]);
    }

    /// @inheritdoc IPremiaAirdrip
    function previewClaimRemaining(address user) external view returns (uint256) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        return _previewClaimRemaining(l, user);
    }

    /// @inheritdoc IPremiaAirdrip
    function previewClaimedAmount(address user) external view returns (uint256) {
        PremiaAirdripStorage.Layout storage l = PremiaAirdripStorage.layout();
        return l.claimed[user];
    }

    function _previewTotalAllocationAmount(
        PremiaAirdripStorage.Layout storage l,
        address user
    ) internal view returns (UD60x18) {
        return l.influence[user] * l.premiaPerInfluence;
    }

    function _previewClaimRemaining(
        PremiaAirdripStorage.Layout storage l,
        address user
    ) internal view returns (uint256) {
        return _previewTotalAllocationAmount(l, user).unwrap() - l.claimed[user];
    }
}
