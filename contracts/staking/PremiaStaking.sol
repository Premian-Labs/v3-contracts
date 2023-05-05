// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {Math} from "@solidstate/contracts/utils/Math.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {WAD} from "../libraries/Constants.sol";
import {IExchangeHelper} from "../utils/IExchangeHelper.sol";
import {IPremiaStaking} from "./IPremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";
import {OFT} from "../layerZero/token/oft/OFT.sol";
import {OFTCore} from "../layerZero/token/oft/OFTCore.sol";
import {IOFTCore} from "../layerZero/token/oft/IOFTCore.sol";
import {BytesLib} from "../layerZero/util/BytesLib.sol";

import {ONE} from "../libraries/Constants.sol";

contract PremiaStaking is IPremiaStaking, OFT {
    using SafeERC20 for IERC20;
    using AddressUtils for address;
    using BytesLib for bytes;

    address internal immutable PREMIA;
    address internal immutable REWARD_TOKEN;
    address internal immutable EXCHANGE_HELPER;

    UD60x18 internal constant DECAY_RATE = UD60x18.wrap(270000000000); // 2.7e-7 -> Distribute around half of the current balance over a month
    uint64 internal constant MAX_PERIOD = 4 * 365 days;
    uint256 internal constant ACC_REWARD_PRECISION = 1e30;
    uint256 internal constant MAX_CONTRACT_DISCOUNT = 0.3e18; // -30%
    uint256 internal constant WITHDRAWAL_DELAY = 10 days;
    uint256 internal constant BPS_CONVERSION = 1e14; // 1e18 / 1e4

    struct UpdateArgsInternal {
        address user;
        uint256 balance;
        uint256 oldPower;
        uint256 newPower;
        uint256 reward;
        uint256 unstakeReward;
    }

    constructor(
        address lzEndpoint,
        address premia,
        address rewardToken,
        address exchangeHelper
    ) OFT(lzEndpoint) {
        PREMIA = premia;
        REWARD_TOKEN = rewardToken;
        EXCHANGE_HELPER = exchangeHelper;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        if (from == address(0) || to == address(0)) return;

        revert PremiaStaking__CantTransfer();
    }

    /// @inheritdoc IPremiaStaking
    function getRewardToken() external view returns (address) {
        return REWARD_TOKEN;
    }

    function estimateSendFee(
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        bool useZro,
        bytes memory adapterParams
    )
        public
        view
        virtual
        override(OFTCore, IOFTCore)
        returns (uint256 nativeFee, uint256 zroFee)
    {
        // Convert bytes to address
        address to;
        assembly {
            to := mload(add(toAddress, 32))
        }

        PremiaStakingStorage.UserInfo storage u = PremiaStakingStorage
            .layout()
            .userInfo[to];

        return
            lzEndpoint.estimateFees(
                dstChainId,
                address(this),
                abi.encode(PT_SEND, to, amount, u.stakePeriod, u.lockedUntil),
                useZro,
                adapterParams
            );
    }

    function _send(
        address from,
        uint16 dstChainId,
        bytes memory,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal virtual override {
        _updateRewards();
        _beforeUnstake(from, amount);

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[from];

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            from
        );

        bytes memory toAddress = abi.encodePacked(from);
        _debitFrom(from, dstChainId, toAddress, amount);

        args.newPower = _calculateUserPower(
            args.balance - amount + args.unstakeReward,
            u.stakePeriod
        );

        _updateUser(l, u, args);

        _lzSend(
            dstChainId,
            abi.encode(
                PT_SEND,
                toAddress,
                amount,
                u.stakePeriod,
                u.lockedUntil
            ),
            refundAddress,
            zroPaymentAddress,
            adapterParams,
            msg.value
        );

        emit SendToChain(from, dstChainId, toAddress, amount);
    }

    function _sendAck(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64,
        bytes memory payload
    ) internal virtual override {
        (
            ,
            bytes memory toAddressBytes,
            uint256 amount,
            uint64 stakePeriod,
            uint64 lockedUntil
        ) = abi.decode(payload, (uint16, bytes, uint256, uint64, uint64));

        address to = toAddressBytes.toAddress(0);

        _creditTo(to, amount, stakePeriod, lockedUntil, true);
        emit ReceiveFromChain(srcChainId, srcAddress, to, amount);
    }

    function _creditTo(
        address toAddress,
        uint256 amount,
        uint64 stakePeriod,
        uint64 creditLockedUntil,
        bool bridge
    ) internal {
        unchecked {
            _updateRewards();

            PremiaStakingStorage.Layout storage l = PremiaStakingStorage
                .layout();
            PremiaStakingStorage.UserInfo storage u = l.userInfo[toAddress];

            UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
                l,
                u,
                toAddress
            );

            uint64 lockedUntil = u.lockedUntil;

            uint64 lockLeft = uint64(
                _calculateWeightedAverage(
                    creditLockedUntil > block.timestamp
                        ? creditLockedUntil - block.timestamp
                        : 0,
                    lockedUntil > block.timestamp
                        ? lockedUntil - block.timestamp
                        : 0,
                    amount + args.unstakeReward,
                    args.balance
                )
            );

            u.lockedUntil = lockedUntil = uint64(block.timestamp) + lockLeft;

            u.stakePeriod = uint64(
                _calculateWeightedAverage(
                    stakePeriod,
                    u.stakePeriod,
                    amount + args.unstakeReward,
                    args.balance
                )
            );

            args.newPower = _calculateUserPower(
                args.balance + amount + args.unstakeReward,
                u.stakePeriod
            );

            _mint(toAddress, amount);

            _updateUser(l, u, args);

            if (bridge) {
                emit BridgeLock(toAddress, u.stakePeriod, lockedUntil);
            } else {
                emit Stake(toAddress, amount, u.stakePeriod, lockedUntil);
            }
        }
    }

    /// @inheritdoc IPremiaStaking
    function addRewards(uint256 amount) external {
        _updateRewards();

        IERC20(REWARD_TOKEN).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        PremiaStakingStorage.layout().availableRewards += amount;

        emit RewardsAdded(amount);
    }

    /// @inheritdoc IPremiaStaking
    function getAvailableRewards()
        external
        view
        returns (uint256 rewards, uint256 unstakeRewards)
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        unchecked {
            rewards = l.availableRewards - getPendingRewards();
        }
        unstakeRewards = l.availableUnstakeRewards;
    }

    /// @inheritdoc IPremiaStaking
    function getPendingRewards() public view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return
            l.availableRewards -
            _decay(l.availableRewards, l.lastRewardUpdate, block.timestamp);
    }

    function _updateRewards() internal {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        if (
            l.lastRewardUpdate == 0 ||
            l.totalPower == 0 ||
            l.availableRewards == 0
        ) {
            l.lastRewardUpdate = block.timestamp;
            return;
        }

        uint256 pendingRewards = getPendingRewards();

        l.accRewardPerShare +=
            (pendingRewards * ACC_REWARD_PRECISION) /
            l.totalPower;

        unchecked {
            l.availableRewards -= pendingRewards;
        }

        l.lastRewardUpdate = block.timestamp;
    }

    /// @inheritdoc IPremiaStaking
    function stakeWithPermit(
        uint256 amount,
        uint64 period,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC2612(PREMIA).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);

        _stake(msg.sender, amount, period);
    }

    /// @inheritdoc IPremiaStaking
    function stake(uint256 amount, uint64 period) external {
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);
        _stake(msg.sender, amount, period);
    }

    /// @inheritdoc IPremiaStaking
    function updateLock(uint64 period) external {
        if (period > MAX_PERIOD) revert PremiaStaking__ExcessiveStakePeriod();

        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[msg.sender];

        uint64 oldPeriod = u.stakePeriod;

        if (period <= oldPeriod) revert PremiaStaking__PeriodTooShort();

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            msg.sender
        );

        unchecked {
            uint64 lockToAdd = period - oldPeriod;
            u.lockedUntil =
                uint64(Math.max(u.lockedUntil, block.timestamp)) +
                lockToAdd;
            u.stakePeriod = period;

            args.newPower = _calculateUserPower(
                args.balance + args.unstakeReward,
                period
            );
        }

        _updateUser(l, u, args);

        emit UpdateLock(msg.sender, oldPeriod, period);
    }

    /// @inheritdoc IPremiaStaking
    function harvestAndStake(
        IPremiaStaking.SwapArgs calldata s,
        uint64 stakePeriod
    ) external {
        uint256 amountRewardToken = _harvest(msg.sender);

        if (amountRewardToken == 0) return;

        IERC20(REWARD_TOKEN).safeTransfer(EXCHANGE_HELPER, amountRewardToken);

        (uint256 amountPremia, ) = IExchangeHelper(EXCHANGE_HELPER)
            .swapWithToken(
                REWARD_TOKEN,
                PREMIA,
                amountRewardToken,
                s.callee,
                s.allowanceTarget,
                s.data,
                s.refundAddress
            );

        if (amountPremia < s.amountOutMin)
            revert PremiaStaking__InsufficientSwapOutput();

        _stake(msg.sender, amountPremia, stakePeriod);
    }

    function _calculateWeightedAverage(
        uint256 A,
        uint256 B,
        uint256 weightA,
        uint256 weightB
    ) internal pure returns (uint256) {
        return (A * weightA + B * weightB) / (weightA + weightB);
    }

    function _stake(
        address toAddress,
        uint256 amount,
        uint64 stakePeriod
    ) internal {
        if (stakePeriod > MAX_PERIOD)
            revert PremiaStaking__ExcessiveStakePeriod();

        unchecked {
            _creditTo(
                toAddress,
                amount,
                stakePeriod,
                uint64(block.timestamp) + stakePeriod,
                false
            );
        }
    }

    /// @inheritdoc IPremiaStaking
    function getPendingUserRewards(
        address user
    ) external view returns (uint256 reward, uint256 unstakeReward) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[user];

        uint256 accRewardPerShare = l.accRewardPerShare;
        if (l.lastRewardUpdate > 0 && l.availableRewards > 0) {
            accRewardPerShare +=
                (getPendingRewards() * ACC_REWARD_PRECISION) /
                l.totalPower;
        }

        uint256 power = _calculateUserPower(_balanceOf(user), u.stakePeriod);

        reward =
            u.reward +
            _calculateReward(accRewardPerShare, power, u.rewardDebt);

        unstakeReward = _calculateReward(
            l.accUnstakeRewardPerShare,
            power,
            u.unstakeRewardDebt
        );
    }

    function harvest() external {
        uint256 amount = _harvest(msg.sender);
        IERC20(REWARD_TOKEN).safeTransfer(msg.sender, amount);
    }

    function _harvest(address account) internal returns (uint256 amount) {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[account];

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            account
        );

        if (args.unstakeReward > 0) {
            args.newPower = _calculateUserPower(
                args.balance + args.unstakeReward,
                u.stakePeriod
            );
        } else {
            args.newPower = args.oldPower;
        }

        _updateUser(l, u, args);

        amount = u.reward;
        u.reward = 0;

        emit Harvest(account, amount);
    }

    function _updateTotalPower(
        PremiaStakingStorage.Layout storage l,
        uint256 oldUserPower,
        uint256 newUserPower
    ) internal {
        if (newUserPower > oldUserPower) {
            l.totalPower += newUserPower - oldUserPower;
        } else if (newUserPower < oldUserPower) {
            l.totalPower -= oldUserPower - newUserPower;
        }
    }

    function _beforeUnstake(address user, uint256 amount) internal virtual {}

    /// @inheritdoc IPremiaStaking
    function earlyUnstake(uint256 amount) external {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        _startWithdraw(
            l,
            l.userInfo[msg.sender],
            amount,
            (ud(amount) * ud(getEarlyUnstakeFee(msg.sender))).unwrap()
        );
    }

    /// @inheritdoc IPremiaStaking
    function getEarlyUnstakeFee(
        address user
    ) public view returns (uint256 feePercentage) {
        uint256 lockedUntil = PremiaStakingStorage
            .layout()
            .userInfo[user]
            .lockedUntil;

        if (lockedUntil <= block.timestamp)
            revert PremiaStaking__StakeNotLocked();

        uint256 lockLeft;

        unchecked {
            lockLeft = lockedUntil - block.timestamp;
            feePercentage = (lockLeft * 0.25e18) / 365 days; // 25% fee per year left
        }

        if (feePercentage > 0.75e18) {
            feePercentage = 0.75e18; // Capped at 75%
        }
    }

    // @dev `getEarlyUnstakeFee` is preferred as it is more precise. This function is kept for backwards compatibility.
    function getEarlyUnstakeFeeBPS(
        address user
    ) external view returns (uint256 feePercentageBPS) {
        return getEarlyUnstakeFee(user) / BPS_CONVERSION;
    }

    /// @inheritdoc IPremiaStaking
    function startWithdraw(uint256 amount) external {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[msg.sender];

        if (u.lockedUntil > block.timestamp)
            revert PremiaStaking__StakeLocked();

        _startWithdraw(l, u, amount, 0);
    }

    function _startWithdraw(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        uint256 amount,
        uint256 fee
    ) internal {
        uint256 amountMinusFee;
        unchecked {
            amountMinusFee = amount - fee;
        }

        if (getAvailablePremiaAmount() < amountMinusFee)
            revert PremiaStaking__NotEnoughLiquidity();

        _updateRewards();
        _beforeUnstake(msg.sender, amount);

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            msg.sender
        );

        _burn(msg.sender, amount);
        l.pendingWithdrawal += amountMinusFee;

        if (fee > 0) {
            l.accUnstakeRewardPerShare +=
                (fee * ACC_REWARD_PRECISION) /
                (l.totalPower - args.oldPower); // User who early unstake doesnt collect any of the fee

            l.availableUnstakeRewards += fee;
        }

        args.newPower = _calculateUserPower(
            args.balance - amount + args.unstakeReward,
            u.stakePeriod
        );

        _updateUser(l, u, args);

        l.withdrawals[msg.sender].amount += amountMinusFee;
        l.withdrawals[msg.sender].startDate = block.timestamp;

        emit Unstake(msg.sender, amount, fee, block.timestamp);
    }

    /// @inheritdoc IPremiaStaking
    function withdraw() external {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 startDate = l.withdrawals[msg.sender].startDate;

        if (startDate == 0) revert PremiaStaking__NoPendingWithdrawal();

        unchecked {
            if (block.timestamp <= startDate + WITHDRAWAL_DELAY)
                revert PremiaStaking__WithdrawalStillPending();
        }

        uint256 amount = l.withdrawals[msg.sender].amount;
        l.pendingWithdrawal -= amount;
        delete l.withdrawals[msg.sender];

        IERC20(PREMIA).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc IPremiaStaking
    function getTotalPower() external view returns (uint256) {
        return PremiaStakingStorage.layout().totalPower;
    }

    /// @inheritdoc IPremiaStaking
    function getUserPower(address user) external view returns (uint256) {
        return
            _calculateUserPower(
                _balanceOf(user),
                PremiaStakingStorage.layout().userInfo[user].stakePeriod
            );
    }

    /// @inheritdoc IPremiaStaking
    function getDiscount(address user) public view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 userPower = _calculateUserPower(
            _balanceOf(user),
            l.userInfo[user].stakePeriod
        );

        if (userPower == 0) return 0;

        // If user is a contract, we use a different formula based on % of total power owned by the contract
        if (user.isContract()) {
            // Require 50% of overall staked power for contract to have max discount
            if (userPower >= l.totalPower >> 1) {
                return MAX_CONTRACT_DISCOUNT;
            } else {
                return
                    (userPower * MAX_CONTRACT_DISCOUNT) / (l.totalPower >> 1);
            }
        }

        IPremiaStaking.StakeLevel[] memory stakeLevels = getStakeLevels();

        uint256 length = stakeLevels.length;

        unchecked {
            for (uint256 i = 0; i < length; i++) {
                IPremiaStaking.StakeLevel memory level = stakeLevels[i];

                if (userPower < level.amount) {
                    uint256 amountPrevLevel;
                    uint256 discountPrevLevel;

                    // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                    if (i > 0) {
                        amountPrevLevel = stakeLevels[i - 1].amount;
                        discountPrevLevel = stakeLevels[i - 1].discount;
                    } else {
                        // If this is the first level, prev level is 0 / 0
                        amountPrevLevel = 0;
                        discountPrevLevel = 0;
                    }

                    uint256 remappedDiscount = level.discount -
                        discountPrevLevel;

                    uint256 remappedAmount = level.amount - amountPrevLevel;
                    uint256 remappedPower = userPower - amountPrevLevel;
                    UD60x18 levelProgress = ud(remappedPower * WAD) /
                        ud(remappedAmount * WAD);

                    return
                        discountPrevLevel +
                        (ud(remappedDiscount) * levelProgress).unwrap();
                }
            }

            // If no match found it means user is >= max possible stake, and therefore has max discount possible
            return stakeLevels[length - 1].discount;
        }
    }

    // @dev `getDiscount` is preferred as it is more precise. This function is kept for backwards compatibility.
    function getDiscountBPS(address user) external view returns (uint256) {
        return getDiscount(user) / BPS_CONVERSION;
    }

    /// @inheritdoc IPremiaStaking
    function getUserInfo(
        address user
    ) external view returns (PremiaStakingStorage.UserInfo memory) {
        return PremiaStakingStorage.layout().userInfo[user];
    }

    function getPendingWithdrawals() external view returns (uint256) {
        return PremiaStakingStorage.layout().pendingWithdrawal;
    }

    function getPendingWithdrawal(
        address user
    )
        external
        view
        returns (uint256 amount, uint256 startDate, uint256 unlockDate)
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        amount = l.withdrawals[user].amount;
        startDate = l.withdrawals[user].startDate;

        unchecked {
            if (startDate > 0) {
                unlockDate = startDate + WITHDRAWAL_DELAY;
            }
        }
    }

    function _decay(
        uint256 pendingRewards,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) internal pure returns (uint256) {
        return
            ((ONE - DECAY_RATE).powu(newTimestamp - oldTimestamp) *
                ud(pendingRewards)).unwrap();
    }

    /// @inheritdoc IPremiaStaking
    function getStakeLevels()
        public
        pure
        returns (IPremiaStaking.StakeLevel[] memory stakeLevels)
    {
        stakeLevels = new IPremiaStaking.StakeLevel[](4);

        stakeLevels[0] = IPremiaStaking.StakeLevel(5000e18, 0.1e18); // -10%
        stakeLevels[1] = IPremiaStaking.StakeLevel(50000e18, 0.25e18); // -25%
        stakeLevels[2] = IPremiaStaking.StakeLevel(500000e18, 0.35e18); // -35%
        stakeLevels[3] = IPremiaStaking.StakeLevel(2500000e18, 0.6e18); // -60%
    }

    /// @inheritdoc IPremiaStaking
    function getStakePeriodMultiplier(
        uint256 period
    ) public pure returns (uint256) {
        unchecked {
            uint256 oneYear = 365 days;

            if (period == 0) return 0.25e18; // x0.25
            if (period >= 4 * oneYear) return 4.25e18; // x4.25

            return 0.25e18 + (period * WAD) / oneYear; // 0.25x + 1.0x per year lockup
        }
    }

    /// @dev `getStakePeriodMultiplier` is preferred as it is more precise. This function is kept for backwards compatibility.
    function getStakePeriodMultiplierBPS(
        uint256 period
    ) external pure returns (uint256) {
        return getStakePeriodMultiplier(period) / BPS_CONVERSION;
    }

    function _calculateUserPower(
        uint256 balance,
        uint64 stakePeriod
    ) internal pure returns (uint256) {
        return
            (ud(balance) * ud(getStakePeriodMultiplier(stakePeriod))).unwrap();
    }

    function _calculateReward(
        uint256 accRewardPerShare,
        uint256 power,
        uint256 rewardDebt
    ) internal pure returns (uint256) {
        return
            ((accRewardPerShare * power) / ACC_REWARD_PRECISION) - rewardDebt;
    }

    function _creditRewards(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        address user,
        uint256 reward,
        uint256 unstakeReward
    ) internal {
        u.reward += reward;

        if (unstakeReward > 0) {
            l.availableUnstakeRewards -= unstakeReward;
            _mint(user, unstakeReward);
            emit EarlyUnstakeRewardCollected(user, unstakeReward);
        }
    }

    function _getInitialUpdateArgsInternal(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        address user
    ) internal view returns (UpdateArgsInternal memory) {
        UpdateArgsInternal memory args;
        args.user = user;
        args.balance = _balanceOf(user);

        if (args.balance > 0) {
            args.oldPower = _calculateUserPower(args.balance, u.stakePeriod);
        }

        args.reward = _calculateReward(
            l.accRewardPerShare,
            args.oldPower,
            u.rewardDebt
        );
        args.unstakeReward = _calculateReward(
            l.accUnstakeRewardPerShare,
            args.oldPower,
            u.unstakeRewardDebt
        );

        return args;
    }

    function _calculateRewardDebt(
        uint256 accRewardPerShare,
        uint256 power
    ) internal pure returns (uint256) {
        return (power * accRewardPerShare) / ACC_REWARD_PRECISION;
    }

    function _updateUser(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        UpdateArgsInternal memory args
    ) internal {
        // Update reward debt
        u.rewardDebt = _calculateRewardDebt(l.accRewardPerShare, args.newPower);
        u.unstakeRewardDebt = _calculateRewardDebt(
            l.accUnstakeRewardPerShare,
            args.newPower
        );

        _creditRewards(l, u, args.user, args.reward, args.unstakeReward);
        _updateTotalPower(l, args.oldPower, args.newPower);
    }

    /// @inheritdoc IPremiaStaking
    function getAvailablePremiaAmount() public view returns (uint256) {
        return
            IERC20(PREMIA).balanceOf(address(this)) -
            PremiaStakingStorage.layout().pendingWithdrawal;
    }
}
