// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IVxPremia} from "./IVxPremia.sol";

library VxPremiaStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.staking.VxPremia");

    struct Vote {
        uint256 amount;
        IVxPremia.VoteVersion version;
        bytes target;
    }

    struct Layout {
        mapping(address => Vote[]) userVotes;
        // Vote version -> Pool identifier -> Vote amount
        mapping(IVxPremia.VoteVersion => mapping(bytes => uint256)) votes;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
