// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";

contract OptionMathTest is Test, Assertions {
    // Normal CDF approximation helper
    function test_helperNormal_ReturnExpectedValue() public {
        // prettier-ignore
        SD59x18[2][22] memory expected = [
            [SD59x18.wrap(-12e18), SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(-11e18), SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(-10e18), SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(-9e18),  SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(-8e18),  SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(-7e18),  SD59x18.wrap(0.999999999999892419e18)],
            [SD59x18.wrap(-6e18),  SD59x18.wrap(0.999999999361484315e18)],
            [SD59x18.wrap(-5e18),  SD59x18.wrap(0.999999554098525700e18)],
            [SD59x18.wrap(-4e18),  SD59x18.wrap(0.999941997571472396e18)],
            [SD59x18.wrap(-3e18),  SD59x18.wrap(0.997937931253017329e18)],
            [SD59x18.wrap(-2e18),  SD59x18.wrap(0.972787315787072559e18)],
            [SD59x18.wrap(-1e18),  SD59x18.wrap(0.836009939237039034e18)],
            [SD59x18.wrap(0e18),   SD59x18.wrap(0.500000000000000000e18)],
            [SD59x18.wrap(1e18),   SD59x18.wrap(0.153320858106603119e18)],
            [SD59x18.wrap(2e18),   SD59x18.wrap(0.018287098844188536e18)],
            [SD59x18.wrap(3e18),   SD59x18.wrap(0.000638104717830912e18)],
            [SD59x18.wrap(4e18),   SD59x18.wrap(0.000004131584646987e18)],
            [SD59x18.wrap(5e18),   SD59x18.wrap(0.000000002182904482e18)],
            [SD59x18.wrap(6e18),   SD59x18.wrap(0.000000000000023121e18)],
            [SD59x18.wrap(7e18),   SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(8e18),   SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(9e18),   SD59x18.wrap(0.000000000000000000e18)]
        ];

        for (uint256 i = 0; i < expected.length; i++) {
            assertApproxEqAbs(
                OptionMath.helperNormal(expected[i][0]).unwrap(),
                expected[i][1].unwrap(),
                UD60x18.wrap(0.0000000000000001e18).unwrap()
            );
        }
    }

    // Normal CDF approximation
    function test_normalCDF_ReturnExpectedValue() public {
        // prettier-ignore
        SD59x18[2][25] memory expected = [
            [SD59x18.wrap(-12e18), SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(-11e18), SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(-10e18), SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(-9e18),  SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(-8e18),  SD59x18.wrap(0.000000000000000000e18)],
            [SD59x18.wrap(-7e18),  SD59x18.wrap(0.000000000000053770e18)],
            [SD59x18.wrap(-6e18),  SD59x18.wrap(0.000000000319269417e18)],
            [SD59x18.wrap(-5e18),  SD59x18.wrap(0.000000224042189416e18)],
            [SD59x18.wrap(-4e18),  SD59x18.wrap(0.000031067006587271e18)],
            [SD59x18.wrap(-3e18),  SD59x18.wrap(0.001350086732406808e18)],
            [SD59x18.wrap(-2e18),  SD59x18.wrap(0.022749891528557986e18)],
            [SD59x18.wrap(-1e18),  SD59x18.wrap(0.158655459434782014e18)],
            [SD59x18.wrap(0e18),   SD59x18.wrap(0.500000000000000000e18)],
            [SD59x18.wrap(1e18),   SD59x18.wrap(0.841344540565218013e18)],
            [SD59x18.wrap(2e18),   SD59x18.wrap(0.977250108471442002e18)],
            [SD59x18.wrap(3e18),   SD59x18.wrap(0.998649913267593225e18)],
            [SD59x18.wrap(4e18),   SD59x18.wrap(0.999968932993412718e18)],
            [SD59x18.wrap(5e18),   SD59x18.wrap(0.999999775957810532e18)],
            [SD59x18.wrap(6e18),   SD59x18.wrap(0.999999999680730611e18)],
            [SD59x18.wrap(7e18),   SD59x18.wrap(0.999999999999946265e18)],
            [SD59x18.wrap(8e18),   SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(9e18),   SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(10e18),  SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(11e18),  SD59x18.wrap(1.000000000000000000e18)],
            [SD59x18.wrap(12e18),  SD59x18.wrap(1.000000000000000000e18)]
        ];

        for (uint256 i = 0; i < expected.length; i++) {
            assertApproxEqAbs(
                OptionMath.normalCdf(expected[i][0]).unwrap(),
                expected[i][1].unwrap(),
                0.0000000000000001e18
            );
        }
    }

    function test_relu_ReturnExpectedValue() public {
        // prettier-ignore
        SD59x18[2][7] memory expected = [
            [SD59x18.wrap(-3.6e18), SD59x18.wrap(0)],
            [SD59x18.wrap(-2.2e18), SD59x18.wrap(0)],
            [SD59x18.wrap(-1.1e18), SD59x18.wrap(0)],
            [SD59x18.wrap(0),       SD59x18.wrap(0)],
            [SD59x18.wrap(1.1e18),  SD59x18.wrap(1.1e18)],
            [SD59x18.wrap(2.1e18),  SD59x18.wrap(2.1e18)],
            [SD59x18.wrap(3.6e18),  SD59x18.wrap(3.6e18)]
        ];

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(
                OptionMath.relu(expected[i][0]),
                expected[i][1].intoUD60x18()
            );
        }
    }

    function _test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices(
        bool isCall
    ) internal {
        UD60x18 strike = UD60x18.wrap(0.8e18);
        UD60x18 timeToMaturity = UD60x18.wrap(0.53e18);
        UD60x18 volAnnualized = UD60x18.wrap(0.732e18);
        UD60x18 riskFreeRate = UD60x18.wrap(0.13e18);

        UD60x18[2][7] memory cases;

        // prettier-ignore
        if (isCall) {
            cases = [
                [UD60x18.wrap(0.001e18), UD60x18.wrap(0)],
                [UD60x18.wrap(0.5e18),   UD60x18.wrap(0.041651656896334266e18)],
                [UD60x18.wrap(0.8e18),   UD60x18.wrap(0.19044728282561157e18)],
                [UD60x18.wrap(1e18),     UD60x18.wrap(0.3361595989775169e18)],
                [UD60x18.wrap(1.2e18),   UD60x18.wrap(0.5037431520530627e18)],
                [UD60x18.wrap(2.2e18),   UD60x18.wrap(1.45850009070196e18)],
                [UD60x18.wrap(11e18),    UD60x18.wrap(10.253264047161903e18)]
            ];
        } else {
            cases = [
                [UD60x18.wrap(0.001e18), UD60x18.wrap(0.745736013930399e18)],
                [UD60x18.wrap(0.5e18),   UD60x18.wrap(0.28838767082673333e18)],
                [UD60x18.wrap(0.8e18),   UD60x18.wrap(0.1371832967560106e18)],
                [UD60x18.wrap(1e18),     UD60x18.wrap(0.08289561290791586e18)],
                [UD60x18.wrap(1.2e18),   UD60x18.wrap(0.05047916598346175e18)],
                [UD60x18.wrap(2.2e18),   UD60x18.wrap(0.005236104632358806e18)],
                [UD60x18.wrap(11e18),    UD60x18.wrap(0.000000061092302312e18)]
            ];
        }

        for (uint256 i = 0; i < cases.length; i++) {
            assertApproxEqAbs(
                OptionMath
                    .blackScholesPrice(
                        cases[i][0],
                        strike,
                        timeToMaturity,
                        volAnnualized,
                        riskFreeRate,
                        isCall
                    )
                    .unwrap(),
                cases[i][1].unwrap(),
                0.00001e18
            );
        }
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices_Call()
        public
    {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices(true);
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices_Put()
        public
    {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices(false);
    }

    function _test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility(
        bool isCall
    ) internal {
        UD60x18 spot = UD60x18.wrap(1.3e18);
        UD60x18 strike = UD60x18.wrap(0.8e18);
        UD60x18 timeToMaturity = UD60x18.wrap(0.53e18);
        UD60x18 riskFreeRate = UD60x18.wrap(0.13e18);

        UD60x18[2][7] memory cases;

        // prettier-ignore
        if (isCall) {
            cases = [
                [UD60x18.wrap(0.001e18), UD60x18.wrap(0.553263986069601e18)],
                [UD60x18.wrap(0.5e18),   UD60x18.wrap(0.5631148171877948e18)],
                [UD60x18.wrap(0.8e18),   UD60x18.wrap(0.6042473564031341e18)],
                [UD60x18.wrap(1e18),     UD60x18.wrap(0.6420186597956653e18)],
                [UD60x18.wrap(1.2e18),   UD60x18.wrap(0.6834990708190316e18)],
                [UD60x18.wrap(2.2e18),   UD60x18.wrap(0.8941443650200548e18)],
                [UD60x18.wrap(11e18),    UD60x18.wrap(1.2999387852636883e18)]
            ];
        } else {
            cases = [
                [UD60x18.wrap(0.001e18), UD60x18.wrap(0)],
                [UD60x18.wrap(0.5e18),   UD60x18.wrap(0.009850831118193633e18)],
                [UD60x18.wrap(0.8e18),   UD60x18.wrap(0.05098337033353306e18)],
                [UD60x18.wrap(1e18),     UD60x18.wrap(0.08875467372606433e18)],
                [UD60x18.wrap(1.2e18),   UD60x18.wrap(0.13023508474943063e18)],
                [UD60x18.wrap(2.2e18),   UD60x18.wrap(0.34088037895045364e18)],
                [UD60x18.wrap(11e18),    UD60x18.wrap(0.7466747991940875e18)]
            ];
        }

        for (uint256 i = 0; i < cases.length; i++) {
            assertApproxEqAbs(
                OptionMath
                    .blackScholesPrice(
                        spot,
                        strike,
                        timeToMaturity,
                        cases[i][0],
                        riskFreeRate,
                        isCall
                    )
                    .unwrap(),
                cases[i][1].unwrap(),
                0.00001e18
            );
        }
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility_Call()
        public
    {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility(true);
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility_Put()
        public
    {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility(false);
    }

    function test_d1d2_ReturnExpectedValue() public {
        UD60x18 strike = UD60x18.wrap(0.8e18);
        UD60x18 timeToMaturity = UD60x18.wrap(0.95e18);
        UD60x18 volAnnualized = UD60x18.wrap(1.61e18);
        UD60x18 riskFreeRate = UD60x18.wrap(0.021e18);

        // prettier-ignore
        SD59x18[3][5] memory cases = [
            [SD59x18.wrap(0.5e18), SD59x18.wrap(0.49781863364936835e18), SD59x18.wrap(-1.0714152558648748e18)],
            [SD59x18.wrap(0.8e18), SD59x18.wrap(0.7973301547720898e18),  SD59x18.wrap(-0.7719037347421535e18)],
            [SD59x18.wrap(1.0e18), SD59x18.wrap(0.9395291939371717e18),  SD59x18.wrap(-0.6297046955770715e18)],
            [SD59x18.wrap(1.2e18), SD59x18.wrap(1.0557142687129861e18),  SD59x18.wrap(-0.5135196208012571e18)],
            [SD59x18.wrap(2.2e18), SD59x18.wrap(1.441976512742106e18),   SD59x18.wrap(-0.12725737677213722e18)]
        ];

        for (uint256 i = 0; i < cases.length; i++) {
            (SD59x18 d1, SD59x18 d2) = OptionMath.d1d2(
                cases[i][0].intoUD60x18(),
                strike,
                timeToMaturity,
                volAnnualized,
                riskFreeRate
            );
            assertApproxEqAbs(
                (d1 - cases[i][1]).unwrap(),
                0,
                0.00000000000001e18
            );
            assertApproxEqAbs(
                (d2 - cases[i][2]).unwrap(),
                0,
                0.00000000000001e18
            );
        }
    }

    function test_isFriday_ReturnFalse_IfNotFriday() public {
        uint32[8] memory timestamps = [
            1674460800,
            1674547200,
            1674633600,
            1674720000,
            1674777599,
            1674864000,
            1674892800,
            1674979200
        ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertFalse(OptionMath.isFriday(timestamps[i]));
        }
    }

    function test_isFriday_ReturnTrue_IfFriday() public {
        uint32[3] memory timestamps = [1674777600, 1674806400, 1674863999];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertTrue(OptionMath.isFriday(timestamps[i]));
        }
    }

    function test_isLastFriday_ReturnFalse_IfNotLastWeekOfMonth() public {
        uint32[6] memory timestamps = [
            1675324800,
            1675411200,
            1675670400,
            1676016000,
            1676620800,
            1676707200
        ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertFalse(OptionMath.isLastFriday(timestamps[i]));
        }
    }

    function test_isLastFriday_ReturnFalse_IfLastWeekOfMonthAndNotFriday()
        public
    {
        uint32[9] memory timestamps = [
            1677139200,
            1677312000,
            1677571200,
            1695625200,
            1695798000,
            1696057200,
            1703491200,
            1703750400,
            1704009600
        ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertFalse(OptionMath.isLastFriday(timestamps[i]));
        }
    }

    function test_isLastFriday_ReturnTrue_IfLastWeekOfMonthAndFriday() public {
        uint32[3] memory timestamps = [1677225600, 1695970800, 1703836800];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertTrue(OptionMath.isLastFriday(timestamps[i]));
        }
    }

    function test_calculateTimeToMaturity_ReturnExpectedValue() public {
        uint256 timestamp = 1683240000;
        uint256 oneWeek = 7 * 24 * 3600;

        vm.warp(timestamp);

        assertEq(
            OptionMath.calculateTimeToMaturity(uint64(timestamp + oneWeek)),
            oneWeek
        );
    }

    function test_calculateStrikeInterval_ReturnExpectedValue() public {
        UD60x18[2][56] memory values = [
            [UD60x18.wrap(1e18), UD60x18.wrap(0.1e18)],
            [UD60x18.wrap(2e18), UD60x18.wrap(0.1e18)],
            [UD60x18.wrap(3e18), UD60x18.wrap(0.1e18)],
            [UD60x18.wrap(4e18), UD60x18.wrap(0.1e18)],
            [UD60x18.wrap(5e18), UD60x18.wrap(0.5e18)],
            [UD60x18.wrap(6e18), UD60x18.wrap(0.5e18)],
            [UD60x18.wrap(7e18), UD60x18.wrap(0.5e18)],
            [UD60x18.wrap(9e18), UD60x18.wrap(0.5e18)],
            [UD60x18.wrap(10e18), UD60x18.wrap(1e18)],
            [UD60x18.wrap(11e18), UD60x18.wrap(1e18)],
            [UD60x18.wrap(33e18), UD60x18.wrap(1e18)],
            [UD60x18.wrap(49e18), UD60x18.wrap(1e18)],
            [UD60x18.wrap(50e18), UD60x18.wrap(5e18)],
            [UD60x18.wrap(51e18), UD60x18.wrap(5e18)],
            [UD60x18.wrap(74e18), UD60x18.wrap(5e18)],
            [UD60x18.wrap(99e18), UD60x18.wrap(5e18)],
            [UD60x18.wrap(100e18), UD60x18.wrap(10e18)],
            [UD60x18.wrap(101e18), UD60x18.wrap(10e18)],
            [UD60x18.wrap(434e18), UD60x18.wrap(10e18)],
            [UD60x18.wrap(499e18), UD60x18.wrap(10e18)],
            [UD60x18.wrap(500e18), UD60x18.wrap(50e18)],
            [UD60x18.wrap(501e18), UD60x18.wrap(50e18)],
            [UD60x18.wrap(871e18), UD60x18.wrap(50e18)],
            [UD60x18.wrap(999e18), UD60x18.wrap(50e18)],
            [UD60x18.wrap(1000e18), UD60x18.wrap(100e18)],
            [UD60x18.wrap(1001e18), UD60x18.wrap(100e18)],
            [UD60x18.wrap(4356e18), UD60x18.wrap(100e18)],
            [UD60x18.wrap(4999e18), UD60x18.wrap(100e18)],
            [UD60x18.wrap(5000e18), UD60x18.wrap(500e18)],
            [UD60x18.wrap(5001e18), UD60x18.wrap(500e18)],
            [UD60x18.wrap(5643e18), UD60x18.wrap(500e18)],
            [UD60x18.wrap(9999e18), UD60x18.wrap(500e18)],
            [UD60x18.wrap(10000e18), UD60x18.wrap(1000e18)],
            [UD60x18.wrap(10001e18), UD60x18.wrap(1000e18)],
            [UD60x18.wrap(35321e18), UD60x18.wrap(1000e18)],
            [UD60x18.wrap(49999e18), UD60x18.wrap(1000e18)],
            [UD60x18.wrap(50000e18), UD60x18.wrap(5000e18)],
            [UD60x18.wrap(50001e18), UD60x18.wrap(5000e18)],
            [UD60x18.wrap(64312e18), UD60x18.wrap(5000e18)],
            [UD60x18.wrap(99999e18), UD60x18.wrap(5000e18)],
            [UD60x18.wrap(100000e18), UD60x18.wrap(10000e18)],
            [UD60x18.wrap(100001e18), UD60x18.wrap(10000e18)],
            [UD60x18.wrap(256110e18), UD60x18.wrap(10000e18)],
            [UD60x18.wrap(499999e18), UD60x18.wrap(10000e18)],
            [UD60x18.wrap(500000e18), UD60x18.wrap(50000e18)],
            [UD60x18.wrap(500001e18), UD60x18.wrap(50000e18)],
            [UD60x18.wrap(862841e18), UD60x18.wrap(50000e18)],
            [UD60x18.wrap(999999e18), UD60x18.wrap(50000e18)],
            [UD60x18.wrap(1000000e18), UD60x18.wrap(100000e18)],
            [UD60x18.wrap(1000001e18), UD60x18.wrap(100000e18)],
            [UD60x18.wrap(4321854e18), UD60x18.wrap(100000e18)],
            [UD60x18.wrap(4999999e18), UD60x18.wrap(100000e18)],
            [UD60x18.wrap(5000000e18), UD60x18.wrap(500000e18)],
            [UD60x18.wrap(5000001e18), UD60x18.wrap(500000e18)],
            [UD60x18.wrap(9418355e18), UD60x18.wrap(500000e18)],
            [UD60x18.wrap(9999999e18), UD60x18.wrap(500000e18)]
        ];

        for (uint256 i = 0; i < values.length; i++) {
            assertEq(
                OptionMath.calculateStrikeInterval(values[i][0]),
                values[i][1]
            );
        }
    }
}
