// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {WAD, ZERO} from "../../libraries/Constants.sol";

import {IOptionReward} from "../optionReward/IOptionReward.sol";

import {IVaultMining} from "./IVaultMining.sol";
import {VaultMiningStorage} from "./VaultMiningStorage.sol";

import {IDualMining} from "../dualMining/IDualMining.sol";
import {IVxPremia} from "../../staking/IVxPremia.sol";
import {IVault} from "../../vault/IVault.sol";
import {IVaultRegistry} from "../../vault/IVaultRegistry.sol";

contract VaultMining is IVaultMining, OwnableInternal {
    using SafeERC20 for IERC20;
    using VaultMiningStorage for VaultMiningStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;

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
    function addRewards(UD60x18 amount) external {
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

        if (vInfo.totalShares == ZERO || vInfo.votes == ZERO) return ZERO;

        return _calculateRewardsUpdate(l, vInfo.lastRewardTimestamp, vInfo.votes);
    }

    /// @inheritdoc IVaultMining
    function getPendingUserRewards(address user, address vault) external view returns (UD60x18) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];
        UserInfo storage uInfo = l.userInfo[vault][user];

        UD60x18 accRewardsPerShare = vInfo.accRewardsPerShare;
        if (block.timestamp > vInfo.lastRewardTimestamp && vInfo.votes > ZERO && vInfo.totalShares > ZERO) {
            UD60x18 rewardsAmount = _calculateRewardsUpdate(l, vInfo.lastRewardTimestamp, vInfo.votes);
            accRewardsPerShare = accRewardsPerShare + (rewardsAmount / vInfo.totalShares);
        }

        return (uInfo.shares * accRewardsPerShare) - uInfo.rewardDebt + uInfo.reward;
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

    function addDualMiningPool(address vault, address dualMining) external onlyOwner {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        updateVault(vault);
        IDualMining(dualMining).init(l.vaultInfo[vault].accRewardsPerShare);
        l.dualMining[vault].add(dualMining);

        emit AddDualMiningPool(vault, dualMining);
    }

    function removeDualMiningPool(address vault, address dualMining) external onlyOwner {
        VaultMiningStorage.layout().dualMining[vault].remove(dualMining);
        emit RemoveDualMiningPool(vault, dualMining);
    }

    /// @inheritdoc IVaultMining
    function getDualMiningPools(address vault) public view returns (address[] memory) {
        return VaultMiningStorage.layout().dualMining[vault].toArray();
    }

    /// @inheritdoc IVaultMining
    function claim(address[] memory vaults) external {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        UD60x18 size;
        for (uint256 i = 0; i < vaults.length; i++) {
            updateUser(msg.sender, vaults[i]);

            UD60x18 rewardAmount = l.userInfo[vaults[i]][msg.sender].reward;
            size = size + rewardAmount;
            l.userInfo[vaults[i]][msg.sender].reward = ZERO;

            emit Claim(msg.sender, vaults[i], rewardAmount);

            address[] memory dualMiningPools = getDualMiningPools(vaults[i]);
            for (uint256 j = 0; j < dualMiningPools.length; j++) {
                IDualMining(dualMiningPools[j]).claim(msg.sender);
            }
        }

        IERC20(PREMIA).approve(OPTION_REWARD, size.unwrap());
        IOptionReward(OPTION_REWARD).underwrite(msg.sender, size);
    }

    function updateVaults() public {
        IVaultRegistry.Vault[] memory vaults = IVaultRegistry(VAULT_REGISTRY).getVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            IVault vault = IVault(vaults[i].vault);
            _updateVault(vaults[i].vault, ud(vault.totalSupply()), vault.getUtilisation());
        }
    }

    /// @inheritdoc IVaultMining
    function updateUser(
        address user,
        address vault,
        UD60x18 newUserShares,
        UD60x18 newTotalShares,
        UD60x18 utilisationRate
    ) external {
        _revertIfNotVault(msg.sender);
        _revertIfNotVault(vault);
        UD60x18 vaultRewards = _updateVault(vault, newTotalShares, utilisationRate);
        _updateUser(user, vault, newUserShares, vaultRewards);
    }

    /// @inheritdoc IVaultMining
    function updateVault(address vault) public {
        _revertIfNotVault(vault);
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        IVault _vault = IVault(vault);
        UD60x18 vaultRewards = _updateVault(vault, ud(_vault.totalSupply()), _vault.getUtilisation());

        address[] memory dualMiningPools = getDualMiningPools(vault);
        for (uint256 i = 0; i < dualMiningPools.length; i++) {
            IDualMining(dualMiningPools[i]).updatePool(vaultRewards, l.vaultInfo[vault].accRewardsPerShare);
        }
    }

    function _updateVault(
        address vault,
        UD60x18 newTotalShares,
        UD60x18 utilisationRate
    ) internal returns (UD60x18 vaultRewards) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];

        if (block.timestamp > vInfo.lastRewardTimestamp) {
            if (vInfo.totalShares > ZERO && vInfo.votes > ZERO) {
                vaultRewards = _calculateRewardsUpdate(l, vInfo.lastRewardTimestamp, vInfo.votes);
                l.rewardsAvailable = l.rewardsAvailable - vaultRewards;
                vInfo.accRewardsPerShare = vInfo.accRewardsPerShare + (vaultRewards / vInfo.totalShares);
            }

            vInfo.lastRewardTimestamp = block.timestamp;
        }

        vInfo.totalShares = newTotalShares;

        _updateVaultAllocation(l, vault, utilisationRate);
    }

    /// @inheritdoc IVaultMining
    function updateUser(address user, address vault) public {
        _revertIfNotVault(vault);

        IVault _vault = IVault(vault);
        UD60x18 vaultRewards = _updateVault(vault, ud(_vault.totalSupply()), _vault.getUtilisation());
        _updateUser(user, vault, ud(_vault.balanceOf(user)), vaultRewards);
    }

    function _updateUser(address user, address vault, UD60x18 newUserShares, UD60x18 vaultRewards) internal {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();
        VaultInfo storage vInfo = l.vaultInfo[vault];
        UserInfo storage uInfo = l.userInfo[vault][user];

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

        uInfo.reward = uInfo.reward + userRewards;
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
