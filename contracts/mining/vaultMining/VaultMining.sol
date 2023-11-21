// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {ZERO, ONE} from "../../libraries/Constants.sol";
import {PRBMathExtra} from "../../libraries/PRBMathExtra.sol";
import {UD50x28, ud50x28} from "../../libraries/UD50x28.sol";

import {IOptionReward} from "../optionReward/IOptionReward.sol";

import {IVaultMining} from "./IVaultMining.sol";
import {VaultMiningStorage} from "./VaultMiningStorage.sol";

import {IDualMining} from "../dualMining/IDualMining.sol";
import {IVxPremia} from "../../staking/IVxPremia.sol";
import {IVault} from "../../vault/IVault.sol";
import {IVaultRegistry} from "../../vault/IVaultRegistry.sol";

contract VaultMining is IVaultMining, OwnableInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using VaultMiningStorage for VaultMiningStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;
    using PRBMathExtra for UD60x18;

    /// @notice Address of the vault registry
    address internal immutable VAULT_REGISTRY;
    /// @notice Address of the PREMIA token
    address internal immutable PREMIA;
    /// @notice Address of the vxPremia token
    address internal immutable VX_PREMIA;
    /// @notice Address of the PREMIA physically settled options
    address internal immutable OPTION_REWARD;

    /// @notice If vote multiplier is zero or not set, we use this value instead
    UD60x18 private constant DEFAULT_VOTE_MULTIPLIER = ONE;

    constructor(address vaultRegistry, address premia, address vxPremia, address optionReward) {
        VAULT_REGISTRY = vaultRegistry;
        PREMIA = premia;
        VX_PREMIA = vxPremia;
        OPTION_REWARD = optionReward;
    }

    /// @inheritdoc IVaultMining
    function addRewards(UD60x18 amount) external nonReentrant {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount.unwrap());
        l.rewardsAvailable = l.rewardsAvailable + amount;
    }

    /// @inheritdoc IVaultMining
    function getRewardsAvailable() external view returns (UD60x18) {
        return VaultMiningStorage.layout().rewardsAvailable;
    }

    /// @inheritdoc IVaultMining
    function getPendingVaultRewards(address vault) external view returns (UD60x18) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];

        UD60x18 rewardAmount = _calculateRewardsUpdate(l);
        return _calculatePendingVaultRewardAmount(l, vInfo, rewardAmount);
    }

    /// @notice Calculate amount of rewards to allocate to the vault since last update
    function _calculatePendingVaultRewardAmount(
        VaultMiningStorage.Layout storage l,
        VaultInfo storage vInfo,
        UD60x18 rewardAmount
    ) internal view returns (UD60x18) {
        if (vInfo.votes == ZERO || vInfo.totalShares == ZERO) return ud(0);

        UD60x18 globalAccRewardsPerVote = l.globalAccRewardsPerVote + (rewardAmount / l.totalVotes);
        return globalAccRewardsPerVote * vInfo.votes - vInfo.rewardDebt;
    }

    /// @inheritdoc IVaultMining
    function getUserRewards(address user) external view returns (UD60x18) {
        return VaultMiningStorage.layout().userRewards[user];
    }

    /// @notice Calculate the amount of rewards to allocate across all vaults since last update
    function _calculateRewardsUpdate(VaultMiningStorage.Layout storage l) internal view returns (UD60x18 rewardAmount) {
        if (block.timestamp <= l.lastUpdate) return ZERO;

        UD50x28 yearsElapsed = ud50x28((block.timestamp - l.lastUpdate) * 1e28) / ud50x28(365 days * 1e28);
        rewardAmount = (yearsElapsed * l.rewardsPerYear.intoUD50x28()).intoUD60x18();

        if (rewardAmount > l.rewardsAvailable) {
            rewardAmount = l.rewardsAvailable;
        }
    }

    /// @notice Calculate the new `accRewardsPerShare` for a vault, based on total rewards to allocate, and share of rewards that vault should get
    function _calculateAccRewardsPerShare(
        VaultMiningStorage.Layout storage l,
        VaultInfo storage vInfo,
        UD60x18 rewardAmount
    ) internal view returns (UD60x18 accRewardsPerShare) {
        if (vInfo.totalShares == ZERO) return vInfo.accRewardsPerShare;

        UD60x18 vaultRewardAmount = _calculatePendingVaultRewardAmount(l, vInfo, rewardAmount);
        return vInfo.accRewardsPerShare + (vaultRewardAmount / vInfo.totalShares);
    }

    /// @inheritdoc IVaultMining
    function getPendingUserRewardsFromVault(address user, address vault) external view returns (UD60x18) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        if (l.lastUpdate == 0) return ZERO;

        VaultInfo storage vInfo = l.vaultInfo[vault];
        UserInfo storage uInfo = l.userInfo[vault][user];

        UD60x18 rewardAmount = _calculateRewardsUpdate(l);
        UD60x18 accRewardsPerShare = _calculateAccRewardsPerShare(l, vInfo, rewardAmount);

        return (uInfo.shares * accRewardsPerShare) - uInfo.rewardDebt;
    }

    /// @inheritdoc IVaultMining
    function getTotalUserRewards(address user) external view returns (UD60x18) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        if (l.lastUpdate == 0) return ZERO;

        UD60x18 totalRewards = l.userRewards[user];
        UD60x18 rewardAmount = _calculateRewardsUpdate(l);

        IVaultRegistry.Vault[] memory vaults = IVaultRegistry(VAULT_REGISTRY).getVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i].vault;
            VaultInfo storage vInfo = l.vaultInfo[vault];
            UserInfo storage uInfo = l.userInfo[vault][user];

            UD60x18 accRewardsPerShare = _calculateAccRewardsPerShare(l, vInfo, rewardAmount);
            totalRewards = totalRewards + (uInfo.shares * accRewardsPerShare) - uInfo.rewardDebt;
        }

        return totalRewards;
    }

    /// @inheritdoc IVaultMining
    function getTotalVotes() external view returns (UD60x18) {
        return VaultMiningStorage.layout().totalVotes;
    }

    /// @inheritdoc IVaultMining
    function getVaultInfo(address vault) external view returns (VaultInfo memory) {
        return VaultMiningStorage.layout().vaultInfo[vault];
    }

    /// @inheritdoc IVaultMining
    function getUserInfo(address user, address vault) external view returns (UserInfo memory) {
        return VaultMiningStorage.layout().userInfo[vault][user];
    }

    /// @inheritdoc IVaultMining
    function getRewardsPerYear() external view returns (UD60x18) {
        return VaultMiningStorage.layout().rewardsPerYear;
    }

    /// @notice Update the yearly emission rate of rewards
    function setRewardsPerYear(UD60x18 rewardsPerYear) external onlyOwner {
        updateVaults();

        VaultMiningStorage.layout().rewardsPerYear = rewardsPerYear;
        emit SetRewardsPerYear(rewardsPerYear);
    }

    /// @inheritdoc IVaultMining
    function getVoteMultiplier(address vault) external view returns (UD60x18) {
        return VaultMiningStorage.layout().voteMultiplier[vault];
    }

    /// @notice Sets the vote multiplier for a specific vault
    function setVoteMultiplier(address vault, UD60x18 voteMultiplier) external onlyOwner {
        VaultMiningStorage.layout().voteMultiplier[vault] = voteMultiplier;
        emit SetVoteMultiplier(vault, voteMultiplier);
    }

    /// @notice Add a dual mining pool for a specific vault
    function addDualMiningPool(address vault, address dualMining) external onlyOwner {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        updateVault(vault);
        IDualMining(dualMining).init(l.vaultInfo[vault].accRewardsPerShare);
        l.dualMining[vault].add(dualMining);

        emit AddDualMiningPool(vault, dualMining);
    }

    /// @notice Removes a dual mining pool from a specific vault
    function removeDualMiningPool(address vault, address dualMining) external onlyOwner {
        VaultMiningStorage.layout().dualMining[vault].remove(dualMining);
        emit RemoveDualMiningPool(vault, dualMining);
    }

    /// @inheritdoc IVaultMining
    function getDualMiningPools(address vault) public view returns (address[] memory) {
        return VaultMiningStorage.layout().dualMining[vault].toArray();
    }

    /// @inheritdoc IVaultMining
    function previewOptionParams() external view returns (UD60x18 strike, uint64 maturity) {
        return IOptionReward(OPTION_REWARD).previewOptionParams();
    }

    /// @inheritdoc IVaultMining
    function claimAll(address[] calldata vaults) external nonReentrant {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        _allocatePendingRewards(l);
        _updateUser(msg.sender, vaults);
        _claimDualMiningRewards(msg.sender, vaults);
        _claimRewards(l, msg.sender, l.userRewards[msg.sender]);
    }

    /// @inheritdoc IVaultMining
    function claim(address[] calldata vaults, UD60x18 amount) external nonReentrant {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        _allocatePendingRewards(l);
        _updateUser(msg.sender, vaults);
        _claimDualMiningRewards(msg.sender, vaults);
        _claimRewards(l, msg.sender, amount);
    }

    /// @notice Claim rewards from all dualMining contracts of given vaults
    function _claimDualMiningRewards(address user, address[] calldata vaults) internal {
        for (uint256 i = 0; i < vaults.length; i++) {
            address[] memory dualMiningPools = getDualMiningPools(vaults[i]);
            for (uint256 j = 0; j < dualMiningPools.length; j++) {
                IDualMining(dualMiningPools[j]).claim(user);
            }
        }
    }

    /// @notice Claim option rewards
    function _claimRewards(VaultMiningStorage.Layout storage l, address user, UD60x18 amount) internal {
        if (amount == ZERO) return;

        if (l.userRewards[user] < amount) revert VaultMining__InsufficientRewards(user, l.userRewards[user], amount);

        l.userRewards[user] = l.userRewards[user] - amount;

        IERC20(PREMIA).approve(OPTION_REWARD, amount.unwrap());
        IOptionReward(OPTION_REWARD).underwrite(user, amount);

        emit Claim(user, amount);
    }

    /// @inheritdoc IVaultMining
    function updateVaults() public nonReentrant {
        IVaultRegistry.Vault[] memory vaults = IVaultRegistry(VAULT_REGISTRY).getVaults();

        _allocatePendingRewards(VaultMiningStorage.layout());

        for (uint256 i = 0; i < vaults.length; i++) {
            IVault vault = IVault(vaults[i].vault);
            _updateVault(vaults[i].vault, ud(vault.totalSupply()));
        }
    }

    /// @inheritdoc IVaultMining
    function updateUser(address user, UD60x18 newUserShares, UD60x18 newTotalShares, UD60x18) external nonReentrant {
        _revertIfNotVault(msg.sender);
        _allocatePendingRewards(VaultMiningStorage.layout());
        _updateUser(user, msg.sender, newUserShares, newTotalShares);
    }

    /// @inheritdoc IVaultMining
    function updateVault(address vault) public nonReentrant {
        _revertIfNotVault(vault);
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        _allocatePendingRewards(VaultMiningStorage.layout());

        IVault _vault = IVault(vault);
        UD60x18 vaultRewards = _updateVault(vault, ud(_vault.totalSupply()));

        address[] memory dualMiningPools = getDualMiningPools(vault);
        for (uint256 i = 0; i < dualMiningPools.length; i++) {
            IDualMining(dualMiningPools[i]).updatePool(vaultRewards, l.vaultInfo[vault].accRewardsPerShare);
        }
    }

    /// @notice Allocate pending rewards from global reward emission
    function _allocatePendingRewards(VaultMiningStorage.Layout storage l) internal {
        if (l.lastUpdate == 0) {
            l.lastUpdate = block.timestamp;
            return;
        }

        UD60x18 rewardAmount = _calculateRewardsUpdate(l);

        l.rewardsAvailable = l.rewardsAvailable - rewardAmount;
        l.lastUpdate = block.timestamp;

        if (rewardAmount == ZERO) return;

        l.globalAccRewardsPerVote = l.globalAccRewardsPerVote + (rewardAmount / l.totalVotes);
    }

    function _updateVault(address vault, UD60x18 newTotalShares) internal returns (UD60x18 vaultRewards) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];

        vaultRewards = l.globalAccRewardsPerVote * vInfo.votes - vInfo.rewardDebt;

        if (vInfo.totalShares == ZERO) {
            // If vault has 0 totalShares, we reallocate vault rewards to available vault rewards, as nobody could claim vault rewards
            l.rewardsAvailable = l.rewardsAvailable + vaultRewards;
            vaultRewards = ud(0);
        } else {
            vInfo.accRewardsPerShare = vInfo.accRewardsPerShare + (vaultRewards / vInfo.totalShares);
        }

        vInfo.totalShares = newTotalShares;
        _updateVaultAllocation(l, vault);

        vInfo.rewardDebt = vInfo.votes * l.globalAccRewardsPerVote;
    }

    /// @inheritdoc IVaultMining
    function updateUser(address user, address vault) external nonReentrant {
        _allocatePendingRewards(VaultMiningStorage.layout());
        _updateUser(user, vault);
    }

    /// @notice Update user rewards for a specific vault
    function _updateUser(address user, address vault) internal {
        _revertIfNotVault(vault);

        IVault _vault = IVault(vault);
        _updateUser(user, vault, ud(_vault.balanceOf(user)), ud(_vault.totalSupply()));
    }

    /// @notice Update user rewards for a list of vaults
    function _updateUser(address user, address[] calldata vaults) internal {
        for (uint256 i = 0; i < vaults.length; i++) {
            _updateUser(user, vaults[i]);
        }
    }

    /// @notice Update user rewards for a specific vault
    function _updateUser(address user, address vault, UD60x18 newUserShares, UD60x18 newTotalShares) internal {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];
        UserInfo storage uInfo = l.userInfo[vault][user];

        UD60x18 vaultRewards = _updateVault(vault, newTotalShares);

        UD60x18 userRewards = (uInfo.shares * vInfo.accRewardsPerShare) - uInfo.rewardDebt;

        address[] memory dualMiningPools = getDualMiningPools(vault);
        for (uint256 i = 0; i < dualMiningPools.length; i++) {
            IDualMining(dualMiningPools[i]).updateUser(
                user,
                uInfo.shares,
                uInfo.rewardDebt,
                vaultRewards,
                userRewards,
                vInfo.accRewardsPerShare
            );
        }

        UD60x18 rewards = (uInfo.shares * vInfo.accRewardsPerShare) - uInfo.rewardDebt;

        if (uInfo.__deprecated_reward > ZERO) {
            rewards = rewards + uInfo.__deprecated_reward;
            uInfo.__deprecated_reward = ZERO;
        }

        if (rewards > ZERO) {
            l.userRewards[user] = l.userRewards[user] + rewards;
            emit AllocateRewards(user, vault, rewards);
        }

        uInfo.rewardDebt = newUserShares * vInfo.accRewardsPerShare;

        if (uInfo.shares != newUserShares) {
            uInfo.shares = newUserShares;
        }
    }

    /// @notice Update vault allocation based on votes and vote multiplier
    function _updateVaultAllocation(VaultMiningStorage.Layout storage l, address vault) internal virtual {
        uint256 votes = IVxPremia(VX_PREMIA).getPoolVotes(IVxPremia.VoteVersion.VaultV3, abi.encodePacked(vault));
        _setVaultVotes(l, VaultVotes({vault: vault, votes: ud(votes)}));
    }

    /// @notice Set new vault votes, scaled by vote multiplier
    function _setVaultVotes(VaultMiningStorage.Layout storage l, VaultVotes memory data) internal {
        if (l.voteMultiplier[data.vault] == ZERO) l.voteMultiplier[data.vault] = DEFAULT_VOTE_MULTIPLIER;
        UD60x18 adjustedVotes = data.votes * l.voteMultiplier[data.vault];
        l.totalVotes = l.totalVotes - l.vaultInfo[data.vault].votes + adjustedVotes;
        l.vaultInfo[data.vault].votes = adjustedVotes;
        emit UpdateVaultVotes(data.vault, data.votes, l.voteMultiplier[data.vault]);
    }

    /// @notice Revert if `addr` is not a vault
    function _revertIfNotVault(address addr) internal view {
        if (IVaultRegistry(VAULT_REGISTRY).isVault(addr) == false) revert VaultMining__NotVault(addr);
    }
}
