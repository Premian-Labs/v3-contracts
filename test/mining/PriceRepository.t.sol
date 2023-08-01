// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {ONE} from "contracts/libraries/Constants.sol";
import {PriceRepository} from "contracts/mining/PriceRepository.sol";
import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {Assertions} from "../Assertions.sol";

contract PriceRepositoryTest is Assertions, Test {
    PriceRepository priceRepository;

    Users users;

    struct Users {
        address user;
        address keeper;
        address pool;
    }

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );

        uint256 fork = vm.createFork(ETH_RPC_URL, 17100000); // Apr-22-2023 06:07:47 AM +UTC
        vm.selectFork(fork);

        users = Users({user: vm.addr(1), keeper: vm.addr(2), pool: vm.addr(3)});

        PriceRepository implementation = new PriceRepository();
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(implementation));
        priceRepository = PriceRepository(address(proxy));

        address[] memory relayers = new address[](1);
        relayers[0] = users.keeper;
        priceRepository.addWhitelistedRelayers(relayers);
    }

    function test_addWhitelistedRelayers_Success() public {
        address[] memory relayers = new address[](1);
        relayers[0] = users.keeper;
        priceRepository.addWhitelistedRelayers(relayers);
    }

    function test_addWhitelistedRelayers_RevertIf_NotOwner() public {
        address[] memory relayers = new address[](1);
        relayers[0] = users.keeper;

        vm.prank(users.keeper);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        priceRepository.addWhitelistedRelayers(relayers);
    }

    function test_removeWhitelistedRelayers_Success() public {
        address[] memory relayers = new address[](1);
        relayers[0] = users.keeper;
        priceRepository.removeWhitelistedRelayers(relayers);
    }

    function test_removeWhitelistedRelayers_RevertIf_NotOwner() public {
        address[] memory relayers = new address[](1);
        relayers[0] = users.keeper;

        vm.prank(users.keeper);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        priceRepository.removeWhitelistedRelayers(relayers);
    }

    function test_setPriceAt_Success() public {
        vm.prank(users.keeper);
        priceRepository.setPriceAt(address(1), address(2), block.timestamp, ONE);
    }

    function test_setPriceAt_RevertIf_KeeperNotAuthorized() public {
        vm.prank(users.user);

        vm.expectRevert(abi.encodeWithSelector(IPriceRepository.PriceRepository__NotAuthorized.selector, users.user));

        priceRepository.setPriceAt(address(1), address(2), block.timestamp, ONE);
    }

    function test_getPrice_Success() public {
        uint256 timestamp = block.timestamp;
        vm.prank(users.keeper);
        priceRepository.setPriceAt(address(1), address(2), timestamp, ONE);
        (UD60x18 price, uint256 _timestamp) = priceRepository.getPrice(address(1), address(2));
        assertEq(price, ONE);
        assertEq(timestamp, _timestamp);
    }

    function test_getPriceAt_Success() public {
        uint256 timestamp = block.timestamp;
        vm.prank(users.keeper);
        priceRepository.setPriceAt(address(1), address(2), timestamp, ONE);
        assertEq(priceRepository.getPriceAt(address(1), address(2), timestamp), ONE);
    }
}
