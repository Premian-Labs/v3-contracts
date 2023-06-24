// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {WAD, ZERO} from "../libraries/Constants.sol";

import {IVaultMining} from "./IVaultMining.sol";
import {IOptionReward} from "./IOptionReward.sol";
import {VaultMiningStorage} from "./VaultMiningStorage.sol";
import {IVxPremia} from "../staking/IVxPremia.sol";

contract VaultMining is IVaultMining, OwnableInternal {
    using SafeERC20 for IERC20;
    using VaultMiningStorage for VaultMiningStorage.Layout;

    /// @notice Address of the vault registry
    address internal immutable VAULT_REGISTRY;
    /// @notice Address of the PREMIA token
    address internal immutable PREMIA;
    /// @notice Address of the vxPremia token
    address internal immutable VX_PREMIA;
    /// @notice Address of the PREMIA physically settled options
    address internal immutable OPTION_REWARD;

    /// @notice If utilization rate is less than this value, we use this value instead as a multiplier on allocation points
    UD60x18 private constant MIN_POINTS_MULTIPLIER = UD60x18.wrap(0.25e18);

    constructor(address vaultRegistry, address premia, address vxPremia, address optionReward) {
        VAULT_REGISTRY = vaultRegistry;
        PREMIA = premia;
        VX_PREMIA = vxPremia;
        OPTION_REWARD = optionReward;
    }

    /// @notice Add rewards to the contract
    function addRewards(UD60x18 amount) external {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount.unwrap());
        l.rewardsAvailable = l.rewardsAvailable + amount;
    }

    function getRewardsAvailable() external view returns (UD60x18) {
        return VaultMiningStorage.layout().rewardsAvailable;
    }

    /// @notice Get pending premia reward for a user on a pool
    /// @param vault Address of the vault
    /// @param user Address of the user
    /// @return Pending rewards for the given user, on the given vault
    function getUserPendingRewards(address vault, address user) external view returns (UD60x18) {
        UD60x18 totalShares = ud(IERC20(vault).totalSupply());
        UD60x18 userShares = ud(IERC20(vault).balanceOf(user));

        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage _vault = l.vaultInfo[vault];

        UserInfo storage _user = l.userInfo[vault][user];
        UD60x18 accRewardsPerShare = _vault.accRewardsPerShare;

        if (block.timestamp > _vault.lastRewardTimestamp && _vault.votes > ZERO && IERC20(vault).totalSupply() > 0) {
            UD60x18 rewardsAmount = _calculateRewardsUpdate(l, _vault.lastRewardTimestamp, _vault.votes);
            accRewardsPerShare = accRewardsPerShare + (rewardsAmount / totalShares);
        }

        return (userShares * accRewardsPerShare) - _user.rewardDebt + _user.reward;
    }

    function _calculateRewardsUpdate(
        VaultMiningStorage.Layout storage l,
        uint256 lastVaultRewardTimestamp,
        UD60x18 vaultVotes
    ) internal view returns (UD60x18 rewardAmount) {
        UD60x18 yearsElapsed = ud((block.timestamp - lastVaultRewardTimestamp) * WAD) / ud(365 days * WAD);
        rewardAmount = (yearsElapsed * l.rewardsPerYear * vaultVotes) / l.totalVotes;

        // If we are running out of rewards to distribute, distribute whats left
        if (rewardAmount > l.rewardsAvailable) {
            rewardAmount = l.rewardsAvailable;
        }
    }

    function getTotalVotes() external view returns (UD60x18) {
        return VaultMiningStorage.layout().totalVotes;
    }

    function getVaultInfo(address vault) external view returns (VaultInfo memory) {
        return VaultMiningStorage.layout().vaultInfo[vault];
    }

    function getRewardsPerYear() external view returns (UD60x18) {
        return VaultMiningStorage.layout().rewardsPerYear;
    }

    function setRewardsPerYear(UD60x18 rewardsPerYear) external {
        VaultMiningStorage.layout().rewardsPerYear = rewardsPerYear;
        emit SetRewardsPerYear(rewardsPerYear);
    }

    function claim(address[] memory vaults) external {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        UD60x18 size;
        for (uint256 i = 0; i < vaults.length; i++) {
            // ToDo : Allocate pending rewards

            UD60x18 rewardAmount = l.userInfo[vaults[i]][msg.sender].reward;
            size = size + rewardAmount;
            l.userInfo[vaults[i]][msg.sender].reward = ZERO;

            emit Claim(msg.sender, vaults[i], rewardAmount);
        }

        IERC20(PREMIA).approve(OPTION_REWARD, size.unwrap());
        IOptionReward(OPTION_REWARD).writeFrom(msg.sender, size);
    }

    function _updateVault(address vault, UD60x18 totalTVL, UD60x18 utilizationRate) internal {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage _vault = l.vaultInfo[vault];

        if (block.timestamp <= _vault.lastRewardTimestamp) return;

        if (totalTVL > ZERO && _vault.votes > ZERO) {
            UD60x18 rewardAmount = _calculateRewardsUpdate(l, _vault.lastRewardTimestamp, _vault.votes);
            l.rewardsAvailable = l.rewardsAvailable - rewardAmount;
            _vault.accRewardsPerShare = _vault.accRewardsPerShare + (rewardAmount / totalTVL);
        }

        _vault.lastRewardTimestamp = block.timestamp;

        _updateVaultAllocation(l, vault, utilizationRate);
    }

    // ToDo : Update
    //    function _allocatePending(
    //        address user,
    //        address vault,
    //        uint256 userTVLOld,
    //        uint256 userTVLNew,
    //        uint256 totalTVL,
    //        uint256 utilizationRate
    //    ) internal {
    //        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
    //        VaultInfo storage vault = l.vaultInfo[vault];
    //        UserInfo storage user = l.userInfo[vault][user];
    //
    //        _updateVault(vault, totalTVL, utilizationRate);
    //
    //        user.reward += (userTVLOld * vault.accRewardsPerShare) - user.rewardDebt;
    //        user.rewardDebt = userTVLOld * vault.accRewardsPerShare;
    //    }

    function _updateVaultAllocation(
        VaultMiningStorage.Layout storage l,
        address vault,
        UD60x18 utilizationRate
    ) internal virtual {
        uint256 votes = IVxPremia(VX_PREMIA).getPoolVotes(IVxPremia.VoteVersion.VaultV3, abi.encode(vault));
        _setVaultVotes(l, VaultVotes({vault: vault, votes: ud(votes), vaultUtilizationRate: utilizationRate}));
    }

    function _setVaultVotes(VaultMiningStorage.Layout storage l, VaultVotes memory data) internal {
        if (data.vaultUtilizationRate < MIN_POINTS_MULTIPLIER) {
            data.vaultUtilizationRate = MIN_POINTS_MULTIPLIER;
        }

        UD60x18 adjustedVotes = data.votes * data.vaultUtilizationRate;

        l.totalVotes = l.totalVotes - l.vaultInfo[data.vault].votes + adjustedVotes;
        l.vaultInfo[data.vault].votes = adjustedVotes;

        // If alloc points set for a new vault, we initialize the last reward timestamp
        if (l.vaultInfo[data.vault].lastRewardTimestamp == 0) {
            l.vaultInfo[data.vault].lastRewardTimestamp = block.timestamp;
        }

        // ToDo : Check if we wanna modify args
        emit UpdateVaultVotes(data.vault, data.votes, data.vaultUtilizationRate);
    }
}
