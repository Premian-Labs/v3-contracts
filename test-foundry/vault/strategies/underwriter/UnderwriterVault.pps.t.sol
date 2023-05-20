// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

abstract contract UnderwriterVaultPpsTest is UnderwriterVaultDeployTest {
    function _getInfos()
        internal
        view
        returns (UnderwriterVaultMock.MaturityInfo[] memory)
    {
        UnderwriterVaultMock.MaturityInfo[]
            memory infos = new UnderwriterVaultMock.MaturityInfo[](4);

        infos[0].maturity = t0;
        infos[0].strikes = new UD60x18[](2);
        infos[0].sizes = new UD60x18[](2);
        infos[0].strikes[0] = ud(900e18);
        infos[0].strikes[1] = ud(2000e18);
        infos[0].sizes[0] = ud(1e18);
        infos[0].sizes[1] = ud(2e18);

        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](2);
        infos[1].sizes = new UD60x18[](2);
        infos[1].strikes[0] = ud(700e18);
        infos[1].strikes[1] = ud(1500e18);
        infos[1].sizes[0] = ud(1e18);
        infos[1].sizes[1] = ud(5e18);

        infos[2].maturity = t2;
        infos[2].strikes = new UD60x18[](2);
        infos[2].sizes = new UD60x18[](2);
        infos[2].strikes[0] = ud(800e18);
        infos[2].strikes[1] = ud(2000e18);
        infos[2].sizes[0] = ud(1e18);
        infos[2].sizes[1] = ud(1e18);

        infos[3].maturity = t3;
        infos[3].strikes = new UD60x18[](1);
        infos[3].sizes = new UD60x18[](1);
        infos[3].strikes[0] = ud(1500e18);
        infos[3].sizes[0] = ud(2e18);

        return infos;
    }

    function test_getTotalLiabilitiesExpired_ReturnExpectedValue() public {
        oracleAdapter.setQuoteFrom(t0, ud(1000e18));
        oracleAdapter.setQuoteFrom(t1, ud(1400e18));
        oracleAdapter.setQuoteFrom(t2, ud(1600e18));
        oracleAdapter.setQuoteFrom(t3, ud(1000e18));

        assertEq(oracleAdapter.quoteFrom(base, quote, t0), ud(1000e18));
        assertEq(oracleAdapter.quoteFrom(base, quote, t1), ud(1400e18));
        assertEq(oracleAdapter.quoteFrom(base, quote, t2), ud(1600e18));
        assertEq(oracleAdapter.quoteFrom(base, quote, t3), ud(1000e18));

        UnderwriterVaultMock.MaturityInfo[]
            memory infos = new UnderwriterVaultMock.MaturityInfo[](4);

        infos[0].maturity = t0;
        infos[0].strikes = new UD60x18[](4);
        infos[0].sizes = new UD60x18[](4);
        infos[0].strikes[0] = ud(800e18);
        infos[0].strikes[1] = ud(900e18);
        infos[0].strikes[2] = ud(1500e18);
        infos[0].strikes[3] = ud(2000e18);
        infos[0].sizes[0] = ud(1e18);
        infos[0].sizes[1] = ud(2e18);
        infos[0].sizes[2] = ud(2e18);
        infos[0].sizes[3] = ud(1e18);

        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](3);
        infos[1].sizes = new UD60x18[](3);
        infos[1].strikes[0] = ud(700e18);
        infos[1].strikes[1] = ud(900e18);
        infos[1].strikes[2] = ud(1500e18);
        infos[1].sizes[0] = ud(1e18);
        infos[1].sizes[1] = ud(5e18);
        infos[1].sizes[2] = ud(1e18);

        infos[2].maturity = t2;
        infos[2].strikes = new UD60x18[](3);
        infos[2].sizes = new UD60x18[](3);
        infos[2].strikes[0] = ud(800e18);
        infos[2].strikes[1] = ud(1500e18);
        infos[2].strikes[2] = ud(2000e18);
        infos[2].sizes[0] = ud(1e18);
        infos[2].sizes[1] = ud(2e18);
        infos[2].sizes[2] = ud(1e18);

        infos[3].maturity = t3;
        infos[3].strikes = new UD60x18[](2);
        infos[3].sizes = new UD60x18[](2);
        infos[3].strikes[0] = ud(900e18);
        infos[3].strikes[1] = ud(1500e18);
        infos[3].sizes[0] = ud(2e18);
        infos[3].sizes[1] = ud(2e18);

        uint256[8] memory timestamps = [
            t0 - 1 days,
            t0,
            t0 + 1 days,
            t1,
            t1 + 1 days,
            t2 + 1 days,
            t3,
            t3 + 1 days
        ];

        UD60x18[8] memory expected = isCallTest
            ? [
                ud(0),
                ud(0.4e18),
                ud(0.4e18),
                ud(0.4e18 + 2.28571428571e18),
                ud(0.4e18 + 2.28571428571e18),
                ud(2.68571428571e18 + 0.625e18),
                ud(2.68571428571e18 + 0.625e18 + 0.2e18),
                ud(2.68571428571e18 + 0.625e18 + 0.2e18)
            ]
            : [
                ud(0),
                ud(2000e18),
                ud(2000e18),
                ud(2000e18 + 100e18),
                ud(2000e18 + 100e18),
                ud(2100e18 + 400e18),
                ud(2100e18 + 400e18 + 1000e18),
                ud(2100e18 + 400e18 + 1000e18)
            ];

        vault.setTimestamp(t0 - 1 days);
        assertEq(vault.getTotalLiabilitiesExpired(), 0);

        vault.setListingsAndSizes(infos);

        for (uint256 i = 0; i < timestamps.length; i++) {
            vault.setTimestamp(timestamps[i]);
            assertApproxEqAbs(
                vault.getTotalLiabilitiesExpired().unwrap(),
                expected[i].unwrap(),
                isCallTest ? 1e8 : 0
            );
        }
    }

    function test_getTotalLiabilitiesUnexpired_ReturnExpectedValue() public {
        setupVolOracleMock();

        vault.setTimestamp(t0 - 1 days);
        assertEq(vault.getTotalLiabilitiesUnexpired(), 0);

        vault.setListingsAndSizes(_getInfos());
        vault.setSpotPrice(ud(1000e18));

        uint256[6] memory timestamps = [
            t0 - 1 days,
            t0,
            t0 + 1 days,
            t2 + 1 days,
            t3,
            t3 + 1 days
        ];

        UD60x18[6] memory expected = isCallTest
            ? [
                ud(0.679618e18),
                ud(0.541099e18),
                ud(0.534583e18),
                ud(0),
                ud(0),
                ud(0)
            ]
            : [
                ud(6576.0e18),
                ud(4537.998e18),
                ud(4531.865e18),
                ud(998.767e18),
                ud(0),
                ud(0)
            ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            vault.setTimestamp(timestamps[i]);
            assertApproxEqAbs(
                vault.getTotalLiabilitiesUnexpired().unwrap(),
                expected[i].unwrap(),
                isCallTest ? 0.000002e18 : 0.002e18
            );
        }
    }
}
