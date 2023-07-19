// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

library VxPremiaStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.staking.VxPremia");

    enum VoteVersion {
        V2 // poolAddress : 20 bytes / isCallPool : 2 bytes
    }

    struct Vote {
        uint256 amount;
        VoteVersion version;
        bytes target;
    }

    struct Layout {
        mapping(address => Vote[]) userVotes;
        // Vote version -> Pool identifier -> Vote amount
        mapping(VoteVersion => mapping(bytes => uint256)) votes;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
