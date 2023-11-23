// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

abstract contract UnderwriterVaultStorageTest is UnderwriterVaultDeployTest {
    function test_convertAssetToUD60x18_ReturnExpectedValue() public {
        UD60x18 value = ud(11.2334e18);
        uint256 valueScaled = toTokenDecimals(value);

        assertEq(vault.fromTokenDecimals(valueScaled), value);
    }

    function test_convertAssetFromUD60x18_ReturnExpectedValue() public {
        UD60x18 value = ud(11.2334e18);
        assertEq(fromTokenDecimals(vault.toTokenDecimals(value)), value);
    }

    function test_getMaturityAfterTimestamp_Success_WhenLengthEqualOne() public {
        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](1);
        infos[0].maturity = 100000;

        vault.setListingsAndSizes(infos);
        assertEq(vault.getMaturityAfterTimestamp(50000), infos[0].maturity);
    }

    function test_getMaturityAfterTimestamp_Success_WhenLengthGreaterThanOne() public {
        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](3);
        infos[0].maturity = 100000;
        infos[1].maturity = 200000;
        infos[2].maturity = 300000;

        vault.setListingsAndSizes(infos);
        assertEq(vault.getMaturityAfterTimestamp(50000), infos[0].maturity);
        assertEq(vault.getMaturityAfterTimestamp(150000), infos[1].maturity);
        assertEq(vault.getMaturityAfterTimestamp(200000), infos[2].maturity);
        assertEq(vault.getMaturityAfterTimestamp(250000), infos[2].maturity);
    }

    function test_getNumberOfUnexpiredListings_ReturnExpectedValue() public {
        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](4);

        infos[0].maturity = t0;
        infos[0].strikes = new UD60x18[](4);
        infos[0].sizes = new UD60x18[](4);
        infos[0].strikes[0] = ud(500e18);
        infos[0].strikes[1] = ud(1000e18);
        infos[0].strikes[2] = ud(1500e18);
        infos[0].strikes[3] = ud(2000e18);
        infos[0].sizes[0] = ud(1e18);
        infos[0].sizes[1] = ud(1e18);
        infos[0].sizes[2] = ud(1e18);
        infos[0].sizes[3] = ud(1e18);

        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](3);
        infos[1].sizes = new UD60x18[](3);
        infos[1].strikes[0] = ud(1000e18);
        infos[1].strikes[1] = ud(1500e18);
        infos[1].strikes[2] = ud(2000e18);
        infos[1].sizes[0] = ud(1e18);
        infos[1].sizes[1] = ud(1e18);
        infos[1].sizes[2] = ud(1e18);

        infos[2].maturity = t2;
        infos[2].strikes = new UD60x18[](3);
        infos[2].sizes = new UD60x18[](3);
        infos[2].strikes[0] = ud(1000e18);
        infos[2].strikes[1] = ud(1500e18);
        infos[2].strikes[2] = ud(2000e18);
        infos[2].sizes[0] = ud(1e18);
        infos[2].sizes[1] = ud(1e18);
        infos[2].sizes[2] = ud(1e18);

        infos[3].maturity = 2 * t2;
        infos[3].strikes = new UD60x18[](2);
        infos[3].sizes = new UD60x18[](2);
        infos[3].strikes[0] = ud(1200e18);
        infos[3].strikes[1] = ud(150e18);
        infos[3].sizes[0] = ud(1e18);
        infos[3].sizes[1] = ud(1e18);

        assertEq(vault.getNumberOfUnexpiredListings(t0 - 1 days), 0);

        vault.setListingsAndSizes(infos);

        uint256[6] memory timestamp = [t0 - 1 days, t0, t0 + 1 days, t2 + 1 days, t3, t3 + 1 days];

        uint256[6] memory expected = [uint256(12), uint256(8), uint256(8), uint256(2), uint256(0), uint256(0)];

        for (uint256 i = 0; i < timestamp.length; i++) {
            assertEq(vault.getNumberOfUnexpiredListings(timestamp[i]), expected[i]);
        }
    }

    function test_contains_ReturnExpectedValue() public {
        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](1);
        infos[0].maturity = 100000;
        infos[0].strikes = new UD60x18[](1);
        infos[0].sizes = new UD60x18[](1);
        infos[0].strikes[0] = ud(1234e18);
        infos[0].sizes[0] = ud(1e18);

        vault.setListingsAndSizes(infos);

        assertTrue(vault.contains(ud(1234e18), 100000));
        assertFalse(vault.contains(ud(1200e18), 100000));
        assertFalse(vault.contains(ud(1200e18), 10000));
    }

    function test_addListing_Success() public {
        // Adds a listing when there are no listings
        assertEq(vault.getNumberOfListings(), 0);

        vault.addListing(ud(1000e18), t1);
        assertTrue(vault.contains(ud(1000e18), t1));

        assertEq(vault.getNumberOfListings(), 1);
        assertEq(vault.getMinMaturity(), t1);
        assertEq(vault.getMaxMaturity(), t1);

        // Adds a listing to an existing maturity
        vault.addListing(ud(2000e18), t1);
        assertTrue(vault.contains(ud(2000e18), t1));

        assertEq(vault.getNumberOfListings(), 2);
        assertEq(vault.getMinMaturity(), t1);
        assertEq(vault.getMaxMaturity(), t1);

        // Adds a listing with a maturity before minMaturity
        vault.addListing(ud(1000e18), t0);
        assertTrue(vault.contains(ud(1000e18), t0));

        assertEq(vault.getNumberOfListings(), 3);
        assertEq(vault.getMinMaturity(), t0);
        assertEq(vault.getMaxMaturity(), t1);

        // Adds a listing with a maturity after maxMaturity
        vault.addListing(ud(1000e18), t2);
        assertTrue(vault.contains(ud(1000e18), t2));

        assertEq(vault.getNumberOfListings(), 4);
        assertEq(vault.getMinMaturity(), t0);
        assertEq(vault.getMaxMaturity(), t2);

        // Will not add a duplicate listing
        vault.addListing(ud(1000e18), t2);
        assertTrue(vault.contains(ud(1000e18), t2));

        assertEq(vault.getNumberOfListings(), 4);
        assertEq(vault.getMinMaturity(), t0);
        assertEq(vault.getMaxMaturity(), t2);
    }

    function test_removeListing_Success() public {
        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](3);

        infos[0].maturity = t0;
        infos[0].strikes = new UD60x18[](2);
        infos[0].sizes = new UD60x18[](2);
        infos[0].strikes[0] = ud(1000e18);
        infos[0].strikes[1] = ud(2000e18);
        infos[0].sizes[0] = ud(0);
        infos[0].sizes[1] = ud(0);

        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](2);
        infos[1].sizes = new UD60x18[](2);
        infos[1].strikes[0] = ud(1000e18);
        infos[1].strikes[1] = ud(2000e18);
        infos[1].sizes[0] = ud(0);
        infos[1].sizes[1] = ud(0);

        infos[2].maturity = t2;
        infos[2].strikes = new UD60x18[](1);
        infos[2].sizes = new UD60x18[](1);
        infos[2].strikes[0] = ud(1000e18);
        infos[2].sizes[0] = ud(0);

        vault.setListingsAndSizes(infos);

        // should adjust and remove maxMaturity when it becomes empty
        assertEq(vault.getNumberOfListings(), 5);

        vault.removeListing(ud(1000e18), t2);
        assertFalse(vault.contains(ud(1000e18), t2));

        assertEq(vault.getNumberOfListingsOnMaturity(t2), 0);
        assertEq(vault.getMinMaturity(), t0);
        assertEq(vault.getMaxMaturity(), t1);

        // should remove strike from minMaturity
        assertEq(vault.getNumberOfListings(), 4);

        vault.removeListing(ud(1000e18), t0);
        assertFalse(vault.contains(ud(1000e18), t0));

        assertEq(vault.getNumberOfListingsOnMaturity(t0), 1);
        assertEq(vault.getMinMaturity(), t0);
        assertEq(vault.getMaxMaturity(), t1);

        // should adjust and remove minMaturity when it becomes empty
        assertEq(vault.getNumberOfListings(), 3);

        vault.removeListing(ud(2000e18), t0);
        assertFalse(vault.contains(ud(2000e18), t0));

        assertEq(vault.getNumberOfListingsOnMaturity(t0), 0);
        assertEq(vault.getMinMaturity(), t1);
        assertEq(vault.getMaxMaturity(), t1);

        // should remove strike from single maturity
        assertEq(vault.getNumberOfListings(), 2);

        vault.removeListing(ud(1000e18), t1);
        assertFalse(vault.contains(ud(1000e18), t1));

        assertEq(vault.getNumberOfListingsOnMaturity(t1), 1);
        assertEq(vault.getMinMaturity(), t1);
        assertEq(vault.getMaxMaturity(), t1);

        // should remove strike from last maturity and leave 0 listings
        assertEq(vault.getNumberOfListings(), 1);

        vault.removeListing(ud(2000e18), t1);
        assertFalse(vault.contains(ud(2000e18), t1));

        assertEq(vault.getNumberOfListingsOnMaturity(t1), 0);
        assertEq(vault.getMinMaturity(), 0);
        assertEq(vault.getMaxMaturity(), 0);

        assertEq(vault.getNumberOfListings(), 0);
    }
}
