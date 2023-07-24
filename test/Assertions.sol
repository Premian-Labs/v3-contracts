// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {StdAssertions} from "forge-std/StdAssertions.sol";

import {SD1x18} from "@prb/math/sd1x18/ValueType.sol";
import {SD59x18} from "@prb/math/sd59x18/ValueType.sol";
import {UD2x18} from "@prb/math/ud2x18/ValueType.sol";
import {UD60x18} from "@prb/math/ud60x18/ValueType.sol";

import {UD50x28} from "contracts/libraries/UD50x28.sol";
import {SD49x28} from "contracts/libraries/SD49x28.sol";

/// @notice Derived from https://github.com/PaulRBerg/prb-math/blob/main/src/test/Assertions.sol
contract Assertions is StdAssertions {
    /*//////////////////////////////////////////////////////////////////////////
                                       SD1X18
    //////////////////////////////////////////////////////////////////////////*/

    function assertEq(SD1x18 a, SD1x18 b) internal {
        assertEq(SD1x18.unwrap(a), SD1x18.unwrap(b));
    }

    function assertEq(SD1x18 a, SD1x18 b, string memory err) internal {
        assertEq(SD1x18.unwrap(a), SD1x18.unwrap(b), err);
    }

    function assertEq(SD1x18 a, int64 b) internal {
        assertEq(SD1x18.unwrap(a), b);
    }

    function assertEq(SD1x18 a, int64 b, string memory err) internal {
        assertEq(SD1x18.unwrap(a), b, err);
    }

    function assertEq(int64 a, SD1x18 b) internal {
        assertEq(a, SD1x18.unwrap(b));
    }

    function assertEq(int64 a, SD1x18 b, string memory err) internal {
        assertEq(a, SD1x18.unwrap(b), err);
    }

    function assertEq(SD1x18[] memory a, SD1x18[] memory b) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(SD1x18[] memory a, SD1x18[] memory b, string memory err) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(SD1x18[] memory a, int64[] memory b) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(SD1x18[] memory a, int64[] memory b, string memory err) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(int64[] memory a, SD1x18[] memory b) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(int64[] memory a, SD1x18[] memory b, string memory err) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       SD59X18
    //////////////////////////////////////////////////////////////////////////*/

    function assertEq(SD59x18 a, SD59x18 b) internal {
        assertEq(SD59x18.unwrap(a), SD59x18.unwrap(b));
    }

    function assertEq(SD59x18 a, SD59x18 b, string memory err) internal {
        assertEq(SD59x18.unwrap(a), SD59x18.unwrap(b), err);
    }

    function assertEq(SD59x18 a, int256 b) internal {
        assertEq(SD59x18.unwrap(a), b);
    }

    function assertEq(SD59x18 a, int256 b, string memory err) internal {
        assertEq(SD59x18.unwrap(a), b, err);
    }

    function assertEq(int256 a, SD59x18 b) internal {
        assertEq(a, SD59x18.unwrap(b));
    }

    function assertEq(int256 a, SD59x18 b, string memory err) internal {
        assertEq(a, SD59x18.unwrap(b), err);
    }

    function assertEq(SD59x18[] memory a, SD59x18[] memory b) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(SD59x18[] memory a, SD59x18[] memory b, string memory err) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(SD59x18[] memory a, int256[] memory b) internal {
        int256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b);
    }

    function assertEq(SD59x18[] memory a, int256[] memory b, string memory err) internal {
        int256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b, err);
    }

    function assertEq(int256[] memory a, SD59x18[] memory b) internal {
        int256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b);
    }

    function assertEq(int256[] memory a, SD59x18[] memory b, string memory err) internal {
        int256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b, err);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       UD2X18
    //////////////////////////////////////////////////////////////////////////*/

    function assertEq(UD2x18 a, UD2x18 b) internal {
        assertEq(UD2x18.unwrap(a), UD2x18.unwrap(b));
    }

    function assertEq(UD2x18 a, UD2x18 b, string memory err) internal {
        assertEq(UD2x18.unwrap(a), UD2x18.unwrap(b), err);
    }

    function assertEq(UD2x18 a, uint64 b) internal {
        assertEq(UD2x18.unwrap(a), uint256(b));
    }

    function assertEq(UD2x18 a, uint64 b, string memory err) internal {
        assertEq(UD2x18.unwrap(a), uint256(b), err);
    }

    function assertEq(uint64 a, UD2x18 b) internal {
        assertEq(uint256(a), UD2x18.unwrap(b));
    }

    function assertEq(uint64 a, UD2x18 b, string memory err) internal {
        assertEq(uint256(a), UD2x18.unwrap(b), err);
    }

    function assertEq(UD2x18[] memory a, UD2x18[] memory b) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(UD2x18[] memory a, UD2x18[] memory b, string memory err) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(UD2x18[] memory a, uint64[] memory b) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(UD2x18[] memory a, uint64[] memory b, string memory err) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(uint64[] memory a, UD2x18[] memory b) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(uint64[] memory a, UD2x18[] memory b, string memory err) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       UD60X18
    //////////////////////////////////////////////////////////////////////////*/

    function assertEq(UD60x18 a, UD60x18 b) internal {
        assertEq(UD60x18.unwrap(a), UD60x18.unwrap(b));
    }

    function assertEq(UD60x18 a, UD60x18 b, string memory err) internal {
        assertEq(UD60x18.unwrap(a), UD60x18.unwrap(b), err);
    }

    function assertEq(UD60x18 a, uint256 b) internal {
        assertEq(UD60x18.unwrap(a), b);
    }

    function assertEq(UD60x18 a, uint256 b, string memory err) internal {
        assertEq(UD60x18.unwrap(a), b, err);
    }

    function assertEq(uint256 a, UD60x18 b) internal {
        assertEq(a, UD60x18.unwrap(b));
    }

    function assertEq(uint256 a, UD60x18 b, string memory err) internal {
        assertEq(a, UD60x18.unwrap(b), err);
    }

    function assertEq(UD60x18[] memory a, UD60x18[] memory b) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(UD60x18[] memory a, UD60x18[] memory b, string memory err) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(UD60x18[] memory a, uint256[] memory b) internal {
        uint256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b);
    }

    function assertEq(UD60x18[] memory a, uint256[] memory b, string memory err) internal {
        uint256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b, err);
    }

    function assertEq(uint256[] memory a, SD59x18[] memory b) internal {
        uint256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b);
    }

    function assertEq(uint256[] memory a, SD59x18[] memory b, string memory err) internal {
        uint256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b, err);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       SD49x28
    //////////////////////////////////////////////////////////////////////////*/

    function assertEq(SD49x28 a, SD49x28 b) internal {
        assertEq(SD49x28.unwrap(a), SD49x28.unwrap(b));
    }

    function assertEq(SD49x28 a, SD49x28 b, string memory err) internal {
        assertEq(SD49x28.unwrap(a), SD49x28.unwrap(b), err);
    }

    function assertEq(SD49x28 a, int256 b) internal {
        assertEq(SD49x28.unwrap(a), b);
    }

    function assertEq(SD49x28 a, int256 b, string memory err) internal {
        assertEq(SD49x28.unwrap(a), b, err);
    }

    function assertEq(int256 a, SD49x28 b) internal {
        assertEq(a, SD49x28.unwrap(b));
    }

    function assertEq(int256 a, SD49x28 b, string memory err) internal {
        assertEq(a, SD49x28.unwrap(b), err);
    }

    function assertEq(SD49x28[] memory a, SD49x28[] memory b) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(SD49x28[] memory a, SD49x28[] memory b, string memory err) internal {
        int256[] memory castedA;
        int256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(SD49x28[] memory a, int256[] memory b) internal {
        int256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b);
    }

    function assertEq(SD49x28[] memory a, int256[] memory b, string memory err) internal {
        int256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b, err);
    }

    function assertEq(int256[] memory a, SD49x28[] memory b) internal {
        int256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b);
    }

    function assertEq(int256[] memory a, SD49x28[] memory b, string memory err) internal {
        int256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b, err);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       UD50x28
    //////////////////////////////////////////////////////////////////////////*/

    function assertEq(UD50x28 a, UD50x28 b) internal {
        assertEq(UD50x28.unwrap(a), UD50x28.unwrap(b));
    }

    function assertEq(UD50x28 a, UD50x28 b, string memory err) internal {
        assertEq(UD50x28.unwrap(a), UD50x28.unwrap(b), err);
    }

    function assertEq(UD50x28 a, uint256 b) internal {
        assertEq(UD50x28.unwrap(a), b);
    }

    function assertEq(UD50x28 a, uint256 b, string memory err) internal {
        assertEq(UD50x28.unwrap(a), b, err);
    }

    function assertEq(uint256 a, UD50x28 b) internal {
        assertEq(a, UD50x28.unwrap(b));
    }

    function assertEq(uint256 a, UD50x28 b, string memory err) internal {
        assertEq(a, UD50x28.unwrap(b), err);
    }

    function assertEq(UD50x28[] memory a, UD50x28[] memory b) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB);
    }

    function assertEq(UD50x28[] memory a, UD50x28[] memory b, string memory err) internal {
        uint256[] memory castedA;
        uint256[] memory castedB;
        assembly {
            castedA := a
            castedB := b
        }
        assertEq(castedA, castedB, err);
    }

    function assertEq(UD50x28[] memory a, uint256[] memory b) internal {
        uint256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b);
    }

    function assertEq(UD50x28[] memory a, uint256[] memory b, string memory err) internal {
        uint256[] memory castedA;
        assembly {
            castedA := a
        }
        assertEq(castedA, b, err);
    }

    function assertEq(uint256[] memory a, SD49x28[] memory b) internal {
        uint256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b);
    }

    function assertEq(uint256[] memory a, SD49x28[] memory b, string memory err) internal {
        uint256[] memory castedB;
        assembly {
            castedB := b
        }
        assertEq(a, b, err);
    }
}
