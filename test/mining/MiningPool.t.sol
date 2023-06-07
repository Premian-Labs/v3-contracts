// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {IMiningPool} from "contracts/mining/MiningPool.sol";
import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
import {MiningPool} from "contracts/mining/MiningPool.sol";
import {MiningPoolFactory} from "contracts/mining/MiningPoolFactory.sol";
import {PriceRepository} from "contracts/mining/PriceRepository.sol";
import {PriceRepositoryProxy} from "contracts/mining/PriceRepositoryProxy.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {Assertions} from "../Assertions.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import "forge-std/console2.sol";

contract MiningPoolTest is Assertions, Test {
    PriceRepository priceRepository;
    MiningPool tokenXUSDCMiningPool;
    MiningPool tokenYUSDCMiningPool;
    uint256 daysToExpiry;

    Users users;

    address tokenX;
    address tokenY;
    address usdc;

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

        PriceRepository implementation = new PriceRepository();
        PriceRepositoryProxy proxy = new PriceRepositoryProxy(address(implementation), users.keeper);
        priceRepository = PriceRepository(address(proxy));

        MiningPool miningPoolImplementation = new MiningPool();
        ProxyUpgradeableOwnable miningPoolProxy = new ProxyUpgradeableOwnable(address(miningPoolImplementation));

        MiningPoolFactory miningPoolFactory = new MiningPoolFactory(address(miningPoolProxy));

        daysToExpiry = 30 days;

        ERC20Mock mockToken = new ERC20Mock("Mock Token", 6);

        tokenX = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70; // PREMIA
        tokenY = address(mockToken); // mock token
        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

        tokenXUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                tokenX,
                usdc,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                ud(0.55e18),
                ud(0.80e18),
                daysToExpiry,
                30 days,
                365 days
            )
        );

        tokenYUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                tokenY,
                usdc,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                ud(0.55e18),
                ud(0.80e18),
                daysToExpiry,
                30 days,
                365 days
            )
        );
    }

    function getMaturity(uint256 timestamp) internal view returns (uint256 maturity) {
        maturity = OptionMath.calculateTimestamp8AMUTC(timestamp) + daysToExpiry;
    }

    function setPrice(uint256 timestamp, UD60x18 price, address base, address quote) internal {
        vm.prank(users.keeper);
        priceRepository.setDailyOpenPrice(base, quote, timestamp, price);
    }

    function scaleDecimals(address base, uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = IERC20Metadata(base).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    function _test_writeFrom_Success(MiningPool miningPool, uint256 size, address base, address quote) internal {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC));
        setPrice(timestamp8AMUTC, ud(1e18), base, quote);

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        miningPool.writeFrom(users.underwriter, users.longReceiver, scaleDecimals(base, size));
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

    function test_writeFrom_Success() public {
        _test_writeFrom_Success(tokenXUSDCMiningPool, 1000000e18, tokenX, usdc);
        _test_writeFrom_Success(tokenYUSDCMiningPool, 1000000e6, tokenY, usdc);
    }

    function _test_writeFrom_OnBehalfOfUnderwriter(
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC));
        setPrice(timestamp8AMUTC, ud(1e18), base, quote);

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        miningPool.setApprovalForAll(users.longReceiver, true);
        vm.stopPrank();

        vm.startPrank(users.longReceiver);
        miningPool.writeFrom(users.underwriter, users.longReceiver, scaleDecimals(base, size));
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
        _test_writeFrom_OnBehalfOfUnderwriter(tokenXUSDCMiningPool, 1000000e18, tokenX, usdc);
        _test_writeFrom_OnBehalfOfUnderwriter(tokenYUSDCMiningPool, 1000000e6, tokenY, usdc);
    }

    function test_writeFrom_RevertIf_OperatorNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__OperatorNotAuthorized.selector, users.longReceiver)
        );

        vm.prank(users.longReceiver);
        tokenXUSDCMiningPool.writeFrom(users.underwriter, users.longReceiver, ud(1000000e18));
    }
}
