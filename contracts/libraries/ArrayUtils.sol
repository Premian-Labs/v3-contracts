// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

library ArrayUtils {
    /// @notice Thrown when attempting to increase array size
    error ArrayUtils__ArrayCannotExpand(uint256 arrayLength, uint256 size);

    /// @notice Resizes the `array` to `size`, reverts if size > array.length
    /// @dev It is not safe to increase array size this way
    function resizeArray(uint8[] memory array, uint256 size) internal pure {
        revertIfTryingToExpand(array.length, size);

        assembly {
            mstore(array, size)
        }
    }

    /// @notice Resizes the `array` to `size`, reverts if size > array.length
    /// @dev It is not safe to increase array size this way
    function resizeArray(uint256[] memory array, uint256 size) internal pure {
        revertIfTryingToExpand(array.length, size);

        assembly {
            mstore(array, size)
        }
    }

    /// @notice Resizes the `array` to `size`, reverts if size > array.length
    /// @dev It is not safe to increase array size this way
    function resizeArray(address[] memory array, uint256 size) internal pure {
        revertIfTryingToExpand(array.length, size);

        assembly {
            mstore(array, size)
        }
    }

    /// @notice Reverts if trying to expand array size, as increasing array size through inline assembly is not safe
    function revertIfTryingToExpand(uint256 currentLength, uint256 targetSize) internal pure {
        if (currentLength == targetSize) return;
        if (currentLength < targetSize) revert ArrayUtils__ArrayCannotExpand(currentLength, targetSize);
    }
}
