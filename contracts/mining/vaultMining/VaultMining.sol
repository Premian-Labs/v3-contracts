// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {WAD, ZERO} from "../../libraries/Constants.sol";

import {IOptionReward} from "../optionReward/IOptionReward.sol";

import {IVaultMining} from "./IVaultMining.sol";
import {VaultMiningStorage} from "./VaultMiningStorage.sol";
import {IVxPremia} from "../../staking/IVxPremia.sol";
import {IVault} from "../../vault/IVault.sol";
import {IVaultRegistry} from "../../vault/IVaultRegistry.sol";

contract VaultMining is IVaultMining, OwnableInternal, ReentrancyGuard {
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

    /// @notice If utilisation rate is less than this value, we use this value instead as a multiplier on allocation points
    UD60x18 private constant MIN_POINTS_MULTIPLIER = UD60x18.wrap(0.25e18);

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
    function getUserRewards(address user) external view returns (UD60x18) {
        return VaultMiningStorage.layout().userRewards[user];
    }

    function _calculateRewardsUpdate(VaultMiningStorage.Layout storage l) internal view returns (UD60x18 rewardAmount) {
        if (block.timestamp <= l.lastUpdate) return ZERO;

        UD60x18 yearsElapsed = ud((block.timestamp - l.lastUpdate) * WAD) / ud(365 days * WAD);
        rewardAmount = yearsElapsed * l.rewardsPerYear;

        if (rewardAmount > l.rewardsAvailable) {
            rewardAmount = l.rewardsAvailable;
        }
    }

    function _calculateAccRewardsPerShare(
        VaultMiningStorage.Layout storage l,
        VaultInfo storage vInfo,
        UD60x18 rewardAmount
    ) internal view returns (UD60x18 accRewardsPerShare) {
        accRewardsPerShare = vInfo.accRewardsPerShare;
        if (vInfo.votes > ZERO && vInfo.totalShares > ZERO) {
            UD60x18 globalAccRewardsPerVote = l.globalAccRewardsPerVote + (rewardAmount / l.totalVotes);
            UD60x18 vaultRewardAmount = globalAccRewardsPerVote * vInfo.votes - vInfo.rewardDebt;
            accRewardsPerShare = accRewardsPerShare + (vaultRewardAmount / vInfo.totalShares);
        }
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

    function setRewardsPerYear(UD60x18 rewardsPerYear) external onlyOwner {
        updateVaults();

        VaultMiningStorage.layout().rewardsPerYear = rewardsPerYear;
        emit SetRewardsPerYear(rewardsPerYear);
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
        _claimRewards(l, msg.sender, l.userRewards[msg.sender]);
    }

    /// @inheritdoc IVaultMining
    function claim(address[] calldata vaults, UD60x18 amount) external nonReentrant {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        _allocatePendingRewards(l);
        _updateUser(msg.sender, vaults);
        _claimRewards(l, msg.sender, amount);
    }

    function _claimRewards(VaultMiningStorage.Layout storage l, address user, UD60x18 amount) internal {
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
            _updateVault(vaults[i].vault, ud(vault.totalSupply()), vault.getUtilisation());
        }
    }

    /// @inheritdoc IVaultMining
    function updateUser(
        address user,
        UD60x18 newUserShares,
        UD60x18 newTotalShares,
        UD60x18 utilisationRate
    ) external nonReentrant {
        _revertIfNotVault(msg.sender);
        _allocatePendingRewards(VaultMiningStorage.layout());
        _updateUser(user, msg.sender, newUserShares, newTotalShares, utilisationRate);
    }

    /// @inheritdoc IVaultMining
    function updateVault(address vault) external nonReentrant {
        _revertIfNotVault(vault);

        _allocatePendingRewards(VaultMiningStorage.layout());

        IVault _vault = IVault(vault);
        _updateVault(vault, ud(_vault.totalSupply()), _vault.getUtilisation());
    }

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

    function _updateVault(address vault, UD60x18 newTotalShares, UD60x18 utilisationRate) internal {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];

        UD60x18 vaultRewardAmount = l.globalAccRewardsPerVote * vInfo.votes - vInfo.rewardDebt;

        if (vInfo.totalShares == ZERO) {
            // If vault has 0 totalShares, we reallocate vault rewards to available vault rewards, as nobody could claim vault rewards
            l.rewardsAvailable = l.rewardsAvailable + vaultRewardAmount;
        } else {
            vInfo.accRewardsPerShare = vInfo.accRewardsPerShare + (vaultRewardAmount / vInfo.totalShares);
        }

        vInfo.totalShares = newTotalShares;
        _updateVaultAllocation(l, vault, utilisationRate);

        vInfo.rewardDebt = vInfo.votes * l.globalAccRewardsPerVote;
    }

    /// @inheritdoc IVaultMining
    function updateUser(address user, address vault) external nonReentrant {
        _allocatePendingRewards(VaultMiningStorage.layout());
        _updateUser(user, vault);
    }

    function _updateUser(address user, address vault) internal {
        _revertIfNotVault(vault);

        IVault _vault = IVault(vault);
        _updateUser(user, vault, ud(_vault.balanceOf(user)), ud(_vault.totalSupply()), _vault.getUtilisation());
    }

    function _updateUser(address user, address[] calldata vaults) internal {
        for (uint256 i = 0; i < vaults.length; i++) {
            _updateUser(user, vaults[i]);
        }
    }

    function _updateUser(
        address user,
        address vault,
        UD60x18 newUserShares,
        UD60x18 newTotalShares,
        UD60x18 utilisationRate
    ) internal {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];
        UserInfo storage uInfo = l.userInfo[vault][user];

        _updateVault(vault, newTotalShares, utilisationRate);

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

    function _updateVaultAllocation(
        VaultMiningStorage.Layout storage l,
        address vault,
        UD60x18 utilisationRate
    ) internal virtual {
        uint256 votes = IVxPremia(VX_PREMIA).getPoolVotes(IVxPremia.VoteVersion.VaultV3, abi.encodePacked(vault));
        _setVaultVotes(l, VaultVotes({vault: vault, votes: ud(votes), vaultUtilisationRate: utilisationRate}));
    }

    function _setVaultVotes(VaultMiningStorage.Layout storage l, VaultVotes memory data) internal {
        if (data.vaultUtilisationRate < MIN_POINTS_MULTIPLIER) {
            data.vaultUtilisationRate = MIN_POINTS_MULTIPLIER;
        }

        UD60x18 adjustedVotes = data.votes * data.vaultUtilisationRate;

        l.totalVotes = l.totalVotes - l.vaultInfo[data.vault].votes + adjustedVotes;
        l.vaultInfo[data.vault].votes = adjustedVotes;

        emit UpdateVaultVotes(data.vault, data.votes, data.vaultUtilisationRate);
    }

    function _revertIfNotVault(address caller) internal view {
        if (IVaultRegistry(VAULT_REGISTRY).isVault(caller) == false) revert VaultMining__NotVault(caller);
    }
}
