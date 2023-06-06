// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {IMiningPool} from "contracts/mining/MiningPool.sol";
import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
import {MiningPool} from "contracts/mining/MiningPool.sol";
import {MiningPoolFactory} from "contracts/mining/MiningPoolFactory.sol";
import {PriceRepository} from "contracts/mining/PriceRepository.sol";
import {PriceRepositoryProxy} from "contracts/mining/PriceRepositoryProxy.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {Assertions} from "../Assertions.sol";

import "forge-std/console2.sol";

contract MiningPoolTest is Assertions, Test {
    PriceRepository priceRepository;
    MiningPool miningPool;
    uint256 daysToExpiry;

    Users users;
    address base;
    address quote;

    struct Users {
        address underwriter;
        address longReceiver;
        address keeper;
    }

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );

        uint256 fork = vm.createFork(ETH_RPC_URL, 17101000); // Apr-22-2023 09:30:23 AM +UTC
        vm.selectFork(fork);

        users = Users({underwriter: vm.addr(1), longReceiver: vm.addr(2), keeper: vm.addr(3)});

        base = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70; // PREMIA
        quote = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

        PriceRepository implementation = new PriceRepository();
        PriceRepositoryProxy proxy = new PriceRepositoryProxy(address(implementation), users.keeper);
        priceRepository = PriceRepository(address(proxy));

        MiningPool miningPoolImplementation = new MiningPool();
        ProxyUpgradeableOwnable miningPoolProxy = new ProxyUpgradeableOwnable(address(miningPoolImplementation));

        MiningPoolFactory miningPoolFactory = new MiningPoolFactory(address(miningPoolProxy));

        daysToExpiry = 30 days;

        miningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                base,
                quote,
                address(priceRepository),
                address(0),
                ud(0.55e18),
                daysToExpiry,
                30 days,
                365 days
            )
        );
    }

    function getMaturity(uint256 timestamp) internal view returns (uint256 maturity) {
        maturity = OptionMath.calculateTimestamp8AMUTC(timestamp) + daysToExpiry;
    }

    function setPrice(uint256 timestamp, UD60x18 price) internal {
        vm.prank(users.keeper);
        priceRepository.setDailyOpenPrice(base, quote, timestamp, price);
    }

    function test_writeFrom_Success() public {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC));
        setPrice(timestamp8AMUTC, ud(1e18));
        uint256 size = 1_000_000;

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        miningPool.writeFrom(users.underwriter, users.longReceiver, size);
        vm.stopPrank();

        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, int128(0.55e18));
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, int128(0.55e18));

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);
        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), size);
    }

    function test_writeFrom_OnBehalfOfUnderwriter() public {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC));
        setPrice(timestamp8AMUTC, ud(1e18));
        uint256 size = 1_000_000;

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        miningPool.setApprovalForAll(users.longReceiver, true);
        vm.stopPrank();

        vm.prank(users.longReceiver);
        miningPool.writeFrom(users.underwriter, users.longReceiver, size);

        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, int128(0.55e18));
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, int128(0.55e18));

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);
        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), size);
    }

    function test_writeFrom_RevertIf_OperatorNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__OperatorNotAuthorized.selector, users.longReceiver)
        );

        vm.prank(users.longReceiver);
        miningPool.writeFrom(users.underwriter, users.longReceiver, 1_000_000);
    }
}
