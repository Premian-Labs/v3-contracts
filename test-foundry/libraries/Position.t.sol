// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";
import {IPosition} from "contracts/libraries/IPosition.sol";

contract PositionTest is Test, Assertions {
    using Position for Position.KeyInternal;

    Position.KeyInternal key;
    address user;

    function setUp() public {
        user = address(123);
        key = Position.KeyInternal({
            owner: user,
            operator: user,
            lower: UD60x18.wrap(0.25e18),
            upper: UD60x18.wrap(0.75e18),
            orderType: Position.OrderType.CSUP,
            isCall: true,
            strike: UD60x18.wrap(1000e18)
        });
    }

    function test_keyHash_ReturnsKeyHash() public {
        assertEq(
            key.keyHash(),
            keccak256(
                abi.encode(
                    key.owner,
                    key.operator,
                    key.lower,
                    key.upper,
                    key.orderType
                )
            )
        );
    }

    function test_isShort_ReturnTrue_IfShort() public {
        assertTrue(Position.isShort(Position.OrderType.CS));
        assertTrue(Position.isShort(Position.OrderType.CSUP));
    }

    function test_isShort_ReturnFalse_IfNotShort() public {
        assertFalse(Position.isShort(Position.OrderType.LC));
    }

    function test_isLong_ReturnTrue_IfLong() public {
        assertTrue(Position.isLong(Position.OrderType.LC));
    }

    function test_isLong_ReturnFalse_IfNotLong() public {
        assertFalse(Position.isLong(Position.OrderType.CS));
        assertFalse(Position.isLong(Position.OrderType.CSUP));
    }

    function test_pieceWiseLinear_Return0_IfLowerGreaterOrEqualPrice() public {
        assertEq(key.pieceWiseLinear(key.lower), ZERO);
        assertEq(key.pieceWiseLinear(key.lower - UD60x18.wrap(1)), ZERO);
    }

    function test_pieceWiseLinear_ReturnExpectedValue_IfPriceInRange() public {
        assertEq(
            key.pieceWiseLinear(UD60x18.wrap(0.3e18)),
            UD60x18.wrap(0.1e18)
        );
        assertEq(
            key.pieceWiseLinear(UD60x18.wrap(0.5e18)),
            UD60x18.wrap(0.5e18)
        );
        assertEq(
            key.pieceWiseLinear(UD60x18.wrap(0.7e18)),
            UD60x18.wrap(0.9e18)
        );
    }

    function test_pieceWiseLinear_Return1_IfPriceGreaterOrEqualUpper() public {
        assertEq(key.pieceWiseLinear(key.upper), ONE);
        assertEq(key.pieceWiseLinear(key.upper + UD60x18.wrap(1)), ONE);
    }

    function test_pieceWiseLinear_RevertIf_LowerGreaterOrEqualUpper() public {
        key.lower = key.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseLinear(ZERO);

        //

        key.lower = key.upper + UD60x18.wrap(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseLinear(ZERO);
    }

    function test_pieceWiseQuadratic_Return0_IfLowerGreaterOrEqualPrice()
        public
    {
        assertEq(key.pieceWiseQuadratic(key.lower), ZERO);
        assertEq(key.pieceWiseQuadratic(key.lower - UD60x18.wrap(1)), ZERO);
    }

    function test_pieceWiseQuadratic_ReturnExpectedValue_IfPriceInRange()
        public
    {
        assertEq(
            key.pieceWiseQuadratic(UD60x18.wrap(0.3e18)),
            UD60x18.wrap(0.0275e18)
        );
        assertEq(
            key.pieceWiseQuadratic(UD60x18.wrap(0.5e18)),
            UD60x18.wrap(0.1875e18)
        );
        assertEq(
            key.pieceWiseQuadratic(UD60x18.wrap(0.7e18)),
            UD60x18.wrap(0.4275e18)
        );
    }

    function test_pieceWiseQuadratic_ReturnAvgPrice_IfPriceGreaterOrEqualUpper()
        public
    {
        UD60x18 avg = key.lower.avg(key.upper);
        assertEq(key.pieceWiseQuadratic(key.upper), avg);
        assertEq(key.pieceWiseQuadratic(key.upper + UD60x18.wrap(1)), avg);
    }

    function test_pieceWiseQuadratic_RevertIf_LowerGreaterOrEqualUpper()
        public
    {
        key.lower = key.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseQuadratic(ZERO);

        //

        key.lower = key.upper + UD60x18.wrap(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseQuadratic(ZERO);
    }
}
