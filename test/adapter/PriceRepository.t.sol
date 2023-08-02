// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {ONE} from "contracts/libraries/Constants.sol";
import {PriceRepositoryMock} from "contracts/test/adapter/PriceRepositoryMock.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {IRelayerAccessManager} from "contracts/relayer/IRelayerAccessManager.sol";

import {Assertions} from "../Assertions.sol";

contract PriceRepositoryTest is Assertions, Test {
    PriceRepositoryMock internal priceRepository;

    address internal user;
    address internal relayer;
    address internal pool;

    function setUp() public {
        user = vm.addr(1);
        relayer = vm.addr(2);
        pool = vm.addr(3);

        PriceRepositoryMock implementation = new PriceRepositoryMock();
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(implementation));
        priceRepository = PriceRepositoryMock(address(proxy));

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;
        priceRepository.addWhitelistedRelayers(relayers);
    }

    function test_setPriceAt_Success() public {
        vm.prank(relayer);
        priceRepository.setPriceAt(address(1), address(2), block.timestamp, ONE);
    }

    function test_setPriceAt_RevertIf_NotAuthorized() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IRelayerAccessManager.RelayerAccessManager__NotWhitelistedRelayer.selector, user)
        );
        priceRepository.setPriceAt(address(1), address(2), block.timestamp, ONE);
    }

    function test___getCachedPriceAt_Success() public {
        uint256 timestamp = block.timestamp;
        vm.prank(relayer);
        priceRepository.setPriceAt(address(1), address(2), timestamp, ONE);
        assertEq(priceRepository.__getCachedPriceAt(address(1), address(2), timestamp), ONE);
    }
}
