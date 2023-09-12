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

    function getRewardsAvailable() external view returns (UD60x18) {
        return VaultMiningStorage.layout().rewardsAvailable;
    }

    /// @inheritdoc IVaultMining
    function getPendingUserRewards(address user, address[] calldata vaults) external view returns (UD60x18) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        UD60x18 totalRewards = l.userRewards[user];

        UD60x18 rewardsAmountOffset;
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];
            VaultInfo storage vInfo = l.vaultInfo[vault];
            UserInfo storage uInfo = l.userInfo[vault][user];

            UD60x18 accRewardsPerShare = vInfo.accRewardsPerShare;
            if (block.timestamp > vInfo.lastRewardTimestamp && vInfo.votes > ZERO && vInfo.totalShares > ZERO) {
                UD60x18 rewardsAmount = _calculateRewardsUpdate(
                    l,
                    vInfo.lastRewardTimestamp,
                    vInfo.votes,
                    rewardsAmountOffset
                );
                accRewardsPerShare = accRewardsPerShare + (rewardsAmount / vInfo.totalShares);
                rewardsAmountOffset = rewardsAmountOffset + rewardsAmount;
            }

            totalRewards = totalRewards + (uInfo.shares * accRewardsPerShare) - uInfo.rewardDebt;
        }

        return totalRewards;
    }

    function _calculateRewardsUpdate(
        VaultMiningStorage.Layout storage l,
        uint256 lastVaultRewardTimestamp,
        UD60x18 vaultVotes,
        UD60x18 rewardsAvailableOffset
    ) internal view returns (UD60x18 rewardAmount) {
        UD60x18 yearsElapsed = ud((block.timestamp - lastVaultRewardTimestamp) * WAD) / ud(365 days * WAD);
        rewardAmount = (yearsElapsed * l.rewardsPerYear * vaultVotes) / l.totalVotes;

        // If we are running out of rewards to distribute, distribute whats left
        // We use `rewardsAvailableOffset` to take into account multiple successive rewards update calculated in `getPendingUserRewards`,
        // and to handle the case where rewards would run out during one of those updates
        if (rewardAmount > l.rewardsAvailable - rewardsAvailableOffset) {
            rewardAmount = l.rewardsAvailable - rewardsAvailableOffset;
        }
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
    function claimAll(address[] calldata vaults) external nonReentrant {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        _updateUser(msg.sender, vaults);
        _claimRewards(l, msg.sender, l.userRewards[msg.sender]);
    }

    /// @inheritdoc IVaultMining
    function claim(address[] calldata vaults, UD60x18 amount) external nonReentrant {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

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
        _updateUser(user, msg.sender, newUserShares, newTotalShares, utilisationRate);
    }

    /// @inheritdoc IVaultMining
    function updateVault(address vault) external nonReentrant {
        _revertIfNotVault(vault);

        IVault _vault = IVault(vault);
        _updateVault(vault, ud(_vault.totalSupply()), _vault.getUtilisation());
    }

    function _updateVault(address vault, UD60x18 newTotalShares, UD60x18 utilisationRate) internal {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];

        if (block.timestamp > vInfo.lastRewardTimestamp) {
            if (vInfo.totalShares > ZERO && vInfo.votes > ZERO) {
                UD60x18 rewardAmount = _calculateRewardsUpdate(l, vInfo.lastRewardTimestamp, vInfo.votes, ud(0));
                l.rewardsAvailable = l.rewardsAvailable - rewardAmount;
                vInfo.accRewardsPerShare = vInfo.accRewardsPerShare + (rewardAmount / vInfo.totalShares);
            }

            vInfo.lastRewardTimestamp = block.timestamp;
        }

        vInfo.totalShares = newTotalShares;

        _updateVaultAllocation(l, vault, utilisationRate);
    }

    /// @inheritdoc IVaultMining
    function updateUser(address user, address vault) external nonReentrant {
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

        // If alloc points set for a new vault, we initialize the last reward timestamp
        if (l.vaultInfo[data.vault].lastRewardTimestamp == 0) {
            l.vaultInfo[data.vault].lastRewardTimestamp = block.timestamp;
        }

        emit UpdateVaultVotes(data.vault, data.votes, data.vaultUtilisationRate);
    }

    function _revertIfNotVault(address caller) internal view {
        if (IVaultRegistry(VAULT_REGISTRY).isVault(caller) == false) revert VaultMining__NotVault(caller);
    }
}
