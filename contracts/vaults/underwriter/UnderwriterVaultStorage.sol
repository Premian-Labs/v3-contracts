pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

library UnderwriterVaultStorage {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeCast for int256;

    bytes32 internal constant STORAGE_SLOT =
    keccak256("premia.contracts.storage.UnderwriterVaultStorage");

    struct Layout {

        // VolatilityOracle address
        address oracle;

        // Whether the vault is underwriting calls or puts
        bool isCall;

        // The total assets that have been included in the pool.
        uint256 totalAssets;
        uint256 totalLocked;

        // (strike, maturity) => number of short contracts
        mapping(uint256 => mapping(uint256 => uint256)) positions;

    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
