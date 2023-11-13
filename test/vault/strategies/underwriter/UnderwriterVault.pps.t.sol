// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

abstract contract UnderwriterVaultPpsTest is UnderwriterVaultDeployTest {
    function getInfos() internal view returns (UnderwriterVaultMock.MaturityInfo[] memory) {
        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](4);

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

    function setupOracleAdapterMock() internal {
        oracleAdapter.setPriceAt(t0, ud(1000e18));
        oracleAdapter.setPriceAt(t1, ud(1400e18));
        oracleAdapter.setPriceAt(t2, ud(1600e18));
        oracleAdapter.setPriceAt(t3, ud(1000e18));
    }

    function test_getTotalLiabilitiesUnexpired_ReturnExpectedValue() public {
        setupVolOracleMock();

        vault.setTimestamp(t0 - 1 days);
        assertEq(vault.getTotalLiabilitiesUnexpired(), 0);

        vault.setListingsAndSizes(getInfos());
        vault.setSpotPrice(ud(1000e18));

        uint256[6] memory timestamps = [t0 - 1 days, t0, t0 + 1 days, t2 + 1 days, t3, t3 + 1 days];

        UD60x18[6] memory expected = isCallTest
            ? [ud(0.679618e18), ud(0.541099e18), ud(0.534583e18), ud(0), ud(0), ud(0)]
            : [ud(6576.0e18), ud(4537.998e18), ud(4531.865e18), ud(998.767e18), ud(0), ud(0)];

        for (uint256 i = 0; i < timestamps.length; i++) {
            vault.setTimestamp(timestamps[i]);
            assertApproxEqAbs(
                vault.getTotalLiabilitiesUnexpired().unwrap(),
                expected[i].unwrap(),
                isCallTest ? 0.000002e18 : 0.002e18
            );
        }
    }

    function test_getPricePerShare_ReturnExpectedValue() public {
        // prettier-ignore
        UD60x18[4][5] memory values = isCallTest
            ? [
                [ud(1e18),        ud(2e18), ud(0),      ud(0)],
                [ud(0.9e18),      ud(2e18), ud(0.2e18), ud(0)],
                [ud(0.98e18),     ud(5e18), ud(0.1e18), ud(0)],
                [ud(0.749874e18), ud(2e18), ud(0.2e18), ud(1.5e18)],
                [ud(0.899916e18), ud(2e18), ud(0),      ud(1e18)]
            ]
            : [
                [ud(1e18),        ud(2e18), ud(0),      ud(0)],
                [ud(0.9e18),      ud(2e18), ud(0.2e18), ud(0)],
                [ud(0.98e18),     ud(5e18), ud(0.1e18), ud(0)],
                [ud(0.884747e18), ud(2e18), ud(0.2e18), ud(1.5e18)],
                [ud(0.989831e18), ud(2e18), ud(0),      ud(1e18)]
            ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < values.length; i++) {
            UD60x18 expected = values[i][0];
            UD60x18 deposit = values[i][1];
            UD60x18 tls = values[i][2];
            UD60x18 tradeSize = values[i][3];

            addDeposit(users.lp, deposit);

            t0 = block.timestamp + 7 days;
            volOracle.setVolatility(base, ud(1500e18), ud(1200e18), ud(19178082191780821), ud(0.51e18));

            assertEq(vault.totalAssets(), toTokenDecimals(deposit));
            assertEq(vault.totalSupply(), deposit);

            vault.increaseTotalLockedSpread(tls);
            vault.setMaxMaturity(t0);

            if (tradeSize > ud(0)) {
                UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](1);
                infos[0].maturity = t0;
                infos[0].strikes = new UD60x18[](1);
                infos[0].sizes = new UD60x18[](1);
                infos[0].strikes[0] = ud(1200e18);
                infos[0].sizes[0] = tradeSize;

                vault.setListingsAndSizes(infos);
                vault.increaseTotalLockedAssets(tradeSize);
            }

            assertApproxEqAbs(vault.getPricePerShare().unwrap(), expected.unwrap(), 0.000002e18);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_getSpotPrice_ReturnExpectedValue() public {
        assertEq(vault.getSpotPrice(), ud(1500e18));
    }

    function test_getSettlementPrice_ReturnExpectedValue() public {
        oracleAdapter.setPriceAt(t0, ud(1000e18));
        oracleAdapter.setPriceAt(t1, ud(1400e18));

        assertEq(vault.getSettlementPrice(t0), ud(1000e18));
        assertEq(vault.getSettlementPrice(t1), ud(1400e18));
    }

    function test_computeAssetsAfterSettlementOfExpiredOptions_ReturnExpectedValue() public {
        setupOracleAdapterMock();

        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](4);

        // total size
        // call: 6 ether
        // put: 7600 ether
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

        // total size
        // call: 7 ether
        // put: 6700 ether
        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](3);
        infos[1].sizes = new UD60x18[](3);
        infos[1].strikes[0] = ud(700e18);
        infos[1].strikes[1] = ud(900e18);
        infos[1].strikes[2] = ud(1500e18);
        infos[1].sizes[0] = ud(1e18);
        infos[1].sizes[1] = ud(5e18);
        infos[1].sizes[2] = ud(1e18);

        // total size
        // call: 4 ether
        // put: 5800 ether
        infos[2].maturity = t2;
        infos[2].strikes = new UD60x18[](3);
        infos[2].sizes = new UD60x18[](3);
        infos[2].strikes[0] = ud(800e18);
        infos[2].strikes[1] = ud(1500e18);
        infos[2].strikes[2] = ud(2000e18);
        infos[2].sizes[0] = ud(1e18);
        infos[2].sizes[1] = ud(2e18);
        infos[2].sizes[2] = ud(1e18);

        // total size
        // call: 4 ether
        // put: 4800 ether
        infos[3].maturity = t3;
        infos[3].strikes = new UD60x18[](2);
        infos[3].sizes = new UD60x18[](2);
        infos[3].strikes[0] = ud(900e18);
        infos[3].strikes[1] = ud(1500e18);
        infos[3].sizes[0] = ud(2e18);
        infos[3].sizes[1] = ud(2e18);

        UD60x18[8] memory totalLockedAssetsExpected = isCallTest
            ? [
                ud(21 ether),
                ud(15 ether),
                ud(15 ether),
                ud(8 ether),
                ud(8 ether),
                ud(4 ether),
                ud(0 ether),
                ud(0 ether)
            ]
            : [
                ud(24900 ether),
                ud(17300 ether),
                ud(17300 ether),
                ud(10600 ether),
                ud(10600 ether),
                ud(4800 ether),
                ud(0 ether),
                ud(0 ether)
            ];

        uint256[8] memory timestamps = [t0 - 1 days, t0, t0 + 1 days, t1, t1 + 1 days, t2 + 1 days, t3, t3 + 1 days];

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

        UD60x18 totalAssets;
        UD60x18 totalAssetsLocked;
        (totalAssets, totalAssetsLocked) = vault.exposed_computeAssetsAfterSettlementOfExpiredOptions();
        assertEq(totalAssets, 0);
        assertEq(totalAssetsLocked, 0);

        UD60x18 totalAssetsInitial = isCallTest ? ud(23 ether) : ud(30000 ether);

        vault.setListingsAndSizes(infos);
        vault.setTotalAssets(totalAssetsInitial);
        vault.setTotalLockedAssets(isCallTest ? ud(21 ether) : ud(24900 ether));

        for (uint256 i = 0; i < timestamps.length; i++) {
            vault.setTimestamp(timestamps[i]);
            (totalAssets, totalAssetsLocked) = vault.exposed_computeAssetsAfterSettlementOfExpiredOptions();
            assertApproxEqAbs(totalAssets.unwrap(), (totalAssetsInitial - expected[i]).unwrap(), isCallTest ? 1e8 : 0);
            assertEq(totalAssetsLocked.unwrap(), totalLockedAssetsExpected[i].unwrap());
        }
    }
}
