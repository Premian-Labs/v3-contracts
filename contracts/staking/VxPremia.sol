// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {PremiaStaking} from "./PremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";
import {VxPremiaStorage} from "./VxPremiaStorage.sol";
import {IVxPremia} from "./IVxPremia.sol";

import {IPoolV2ProxyManager} from "./IPoolV2ProxyManager.sol";
import {IVaultRegistry} from "../vault/IVaultRegistry.sol";

/// @author Premia
/// @title A contract allowing you to use your locked Premia as voting power for mining weights
contract VxPremia is IVxPremia, PremiaStaking {
    /// @notice The proxy manager contract used to deploy PremiaV2 pools
    address private immutable PROXY_MANAGER_V2;
    /// @notice The vault registry contract for PremiaV3 vaults
    address private immutable VAULT_REGISTRY;

    constructor(
        address proxyManager,
        address lzEndpoint,
        address premia,
        address rewardToken,
        address exchangeHelper,
        address vaultRegistry
    ) PremiaStaking(lzEndpoint, premia, rewardToken, exchangeHelper) {
        PROXY_MANAGER_V2 = proxyManager;
        VAULT_REGISTRY = vaultRegistry;
    }

    function _beforeUnstake(address user, uint256 amount) internal override {
        uint256 votingPowerUnstaked = _calculateUserPower(
            amount,
            PremiaStakingStorage.layout().userInfo[user].stakePeriod
        );

        _subtractExtraUserVotes(VxPremiaStorage.layout(), user, votingPowerUnstaked);
    }

    /// @notice subtract user votes, starting from the end of the list, if not enough voting power is left after amountUnstaked is unstaked
    function _subtractExtraUserVotes(VxPremiaStorage.Layout storage l, address user, uint256 amountUnstaked) internal {
        uint256 votingPower = _calculateUserPower(
            _balanceOf(user),
            PremiaStakingStorage.layout().userInfo[user].stakePeriod
        );
        uint256 votingPowerUsed = _calculateUserVotingPowerUsed(user);
        uint256 votingPowerLeftAfterUnstake = votingPower - amountUnstaked;

        unchecked {
            if (votingPowerUsed > votingPowerLeftAfterUnstake) {
                _subtractUserVotes(l, user, votingPowerUsed - votingPowerLeftAfterUnstake);
            }
        }
    }

    /// @notice subtract user votes, starting from the end of the list
    function _subtractUserVotes(VxPremiaStorage.Layout storage l, address user, uint256 amount) internal {
        VxPremiaStorage.Vote[] storage userVotes = l.userVotes[user];

        unchecked {
            for (uint256 i = userVotes.length; i > 0; ) {
                VxPremiaStorage.Vote memory vote = userVotes[--i];

                uint256 votesRemoved;

                if (amount < vote.amount) {
                    votesRemoved = amount;
                    userVotes[i].amount -= amount;
                } else {
                    votesRemoved = vote.amount;
                    userVotes.pop();
                }

                amount -= votesRemoved;

                l.votes[vote.version][vote.target] -= votesRemoved;
                emit RemoveVote(user, vote.version, vote.target, votesRemoved);

                if (amount == 0) break;
            }
        }
    }

    function _calculateUserVotingPowerUsed(address user) internal view returns (uint256 votingPowerUsed) {
        VxPremiaStorage.Vote[] memory userVotes = VxPremiaStorage.layout().userVotes[user];

        unchecked {
            for (uint256 i = 0; i < userVotes.length; i++) {
                votingPowerUsed += userVotes[i].amount;
            }
        }
    }

    /// @inheritdoc IVxPremia
    function getPoolVotes(VoteVersion version, bytes calldata target) external view returns (uint256) {
        return VxPremiaStorage.layout().votes[version][target];
    }

    /// @inheritdoc IVxPremia
    function getUserVotes(address user) external view returns (VxPremiaStorage.Vote[] memory) {
        return VxPremiaStorage.layout().userVotes[user];
    }

    /// @inheritdoc IVxPremia
    function castVotes(VxPremiaStorage.Vote[] calldata votes) external nonReentrant {
        VxPremiaStorage.Layout storage l = VxPremiaStorage.layout();

        uint256 userVotingPower = _calculateUserPower(
            _balanceOf(msg.sender),
            PremiaStakingStorage.layout().userInfo[msg.sender].stakePeriod
        );

        VxPremiaStorage.Vote[] storage userVotes = l.userVotes[msg.sender];

        // Remove previous votes
        _resetUserVotes(l, userVotes, msg.sender);

        address[] memory poolList;
        if (PROXY_MANAGER_V2 != address(0)) {
            poolList = IPoolV2ProxyManager(PROXY_MANAGER_V2).getPoolList();
        }

        // Cast new votes
        uint256 votingPowerUsed = 0;
        for (uint256 i = 0; i < votes.length; i++) {
            VxPremiaStorage.Vote memory vote = votes[i];

            votingPowerUsed += vote.amount;
            if (votingPowerUsed > userVotingPower) revert VxPremia__NotEnoughVotingPower();

            if (
                vote.version > VoteVersion.VaultV3 ||
                (vote.version == VoteVersion.V2 && vote.target.length != 21) || // abi.encodePacked on [address, bool] uses 20 bytes for the address and 1 byte for the bool
                (vote.version == VoteVersion.VaultV3 && vote.target.length != 20)
            ) revert VxPremia__InvalidVoteTarget();

            // Check that the pool address is valid
            address contractAddress = address(
                uint160(uint256(bytes32(vote.target)) >> 96) // We need to shift by 96, as we want the 160 most significant bits, which are the pool address
            );

            bool isValid = false;
            if (vote.version == VoteVersion.V2 && PROXY_MANAGER_V2 != address(0)) {
                for (uint256 j = 0; j < poolList.length; j++) {
                    if (contractAddress == poolList[j]) {
                        isValid = true;
                        break;
                    }
                }
            } else if (vote.version == VoteVersion.VaultV3 && VAULT_REGISTRY != address(0)) {
                // Chains other than Arbitrum dont have VAULT_REGISTRY
                isValid = IVaultRegistry(VAULT_REGISTRY).isVault(contractAddress);
            }

            if (isValid == false) revert VxPremia__InvalidPoolAddress();

            userVotes.push(vote);
            l.votes[vote.version][vote.target] += vote.amount;

            emit AddVote(msg.sender, vote.version, vote.target, vote.amount);
        }
    }

    function _resetUserVotes(
        VxPremiaStorage.Layout storage l,
        VxPremiaStorage.Vote[] storage userVotes,
        address user
    ) internal {
        for (uint256 i = userVotes.length; i > 0; ) {
            VxPremiaStorage.Vote memory vote = userVotes[--i];

            l.votes[vote.version][vote.target] -= vote.amount;
            emit RemoveVote(user, vote.version, vote.target, vote.amount);

            userVotes.pop();
        }
    }

    function resetUserVotes(address user) external onlyOwner {
        VxPremiaStorage.Layout storage l = VxPremiaStorage.layout();
        VxPremiaStorage.Vote[] storage userVotes = l.userVotes[user];
        _resetUserVotes(l, userVotes, user);
    }
}
