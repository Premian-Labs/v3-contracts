// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {IMiningPool} from "contracts/mining/MiningPool.sol";
import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
import {MiningPool} from "contracts/mining/MiningPool.sol";
import {MiningPoolFactory} from "contracts/mining/MiningPoolFactory.sol";
import {PriceRepository} from "contracts/mining/PriceRepository.sol";
import {PriceRepositoryProxy} from "contracts/mining/PriceRepositoryProxy.sol";

import {Assertions} from "../Assertions.sol";

import "forge-std/console2.sol";

contract MiningPoolTest is Assertions, Test {
    using SafeCast for int256;
    using SafeCast for uint256;

    PriceRepository priceRepository;

    MiningPool premiaUSDCMiningPool;
    MiningPool wbtcUSDCMiningPool;
    MiningPool premiaWETHMiningPool;

    Users users;

    address premia;
    address weth;
    address wbtc;
    address usdc;

    Data[3] _data;

    struct Data {
        UD60x18 discount;
        UD60x18 spot;
        UD60x18 settlementITM;
        UD60x18 penalty;
        uint256 expiryDuration;
        uint256 exerciseDuration;
        uint256 lockupDuration;
    }

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

        _data[0] = Data(ud(0.55e18), ud(1e18), ud(2e18), ud(0.80e18), 30 days, 30 days, 365 days);
        _data[1] = Data(ud(0.1e18), ud(30000e18), ud(35000e18), ud(0.20e18), 30 days, 90 days, 30 days);
        //        data[2] = Data(0.90e18,  ud(0.80e18), 30 days, 30 days, 365 days);

        premia = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70; // PREMIA (18 decimals)
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // PREMIA (18 decimals)
        wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC (8 decimals)
        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC (6 decimals)

        premiaUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                premia,
                usdc,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                _data[0].discount,
                _data[0].penalty,
                _data[0].expiryDuration,
                _data[0].exerciseDuration,
                _data[0].lockupDuration
            )
        );

        wbtcUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                wbtc,
                usdc,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                _data[1].discount,
                _data[1].penalty,
                _data[1].expiryDuration,
                _data[1].exerciseDuration,
                _data[1].lockupDuration
            )
        );

        //        premiaWETHMiningPool = MiningPool(
        //            miningPoolFactory.deployMiningPool(
        //                premia,
        //                weth,
        //                address(priceRepository),
        //                // TODO: deploy payment splitter
        //                address(1),
        //                ud(strike),
        //                penalty,
        //                expiryDuration,
        //                180 days,
        //                180 days
        //            )
        //        );
    }

    function getMaturity(uint256 timestamp, uint256 expiryDuration) internal view returns (uint256 maturity) {
        maturity = OptionMath.calculateTimestamp8AMUTC(timestamp) + expiryDuration;
    }

    function setPrice(uint256 timestamp, UD60x18 price, address base, address quote) internal {
        vm.prank(users.keeper);
        priceRepository.setDailyOpenPrice(base, quote, timestamp, price);
    }

    function scaleDecimalsTo(address token, uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    function scaleDecimalsFrom(address token, UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    function _test_writeFrom_Success(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC, data.expiryDuration));
        setPrice(timestamp8AMUTC, data.spot, base, quote);

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        miningPool.writeFrom(users.underwriter, users.longReceiver, ud(size));
        vm.stopPrank();

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), size);
    }

    function test_writeFrom_Success() public {
        _test_writeFrom_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_writeFrom_Success(_data[1], wbtcUSDCMiningPool, 1000000e8, wbtc, usdc);
    }

    function _test_writeFrom_OnBehalfOfUnderwriter(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC, data.expiryDuration));
        setPrice(timestamp8AMUTC, data.spot, base, quote);

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        miningPool.setApprovalForAll(users.longReceiver, true);
        vm.stopPrank();

        vm.startPrank(users.longReceiver);
        miningPool.writeFrom(users.underwriter, users.longReceiver, ud(size));
        vm.stopPrank();

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), size);
    }

    function test_writeFrom_OnBehalfOfUnderwriter() public {
        _test_writeFrom_OnBehalfOfUnderwriter(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_writeFrom_OnBehalfOfUnderwriter(_data[1], wbtcUSDCMiningPool, 1000000e8, wbtc, usdc);
    }

    function test_writeFrom_RevertIf_OperatorNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__OperatorNotAuthorized.selector, users.longReceiver)
        );

        vm.prank(users.longReceiver);
        premiaUSDCMiningPool.writeFrom(users.underwriter, users.longReceiver, ud(1000000e18));
    }

    function _test_exercise_Success(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = uint64(getMaturity(timestamp8AMUTC, data.expiryDuration));
        setPrice(timestamp8AMUTC, data.spot, base, quote);

        deal(base, users.underwriter, size);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), size);
        UD60x18 _size = ud(size);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        vm.warp(maturity);

        timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        setPrice(timestamp8AMUTC, data.settlementITM, base, quote);

        UD60x18 _strike = data.discount * data.spot;
        int128 strike = _strike.unwrap().toInt256().toInt128();

        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        vm.startPrank(users.longReceiver);
        uint256 exerciseCost = scaleDecimalsFrom(quote, (scaleDecimalsTo(base, size) * _strike));
        deal(quote, users.longReceiver, exerciseCost);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), exerciseCost);

        IERC20(quote).approve(address(miningPool), exerciseCost);
        miningPool.exercise(longTokenId, _size);
        vm.stopPrank();

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), 0);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), 0);
        // TODO: assertEq(IERC20(quote).balanceOf(address(vxPREMIA)), 0.9e18 * exerciseCost);
        // TODO: assertEq(IERC20(quote).balanceOf(address(TREASURY)), 0.1e18 * exerciseCost);

        assertEq(IERC20(base).balanceOf(address(users.longReceiver)), size);
        assertEq(IERC20(base).balanceOf(address(miningPool)), 0);
    }

    function test_exercise_Success() public {
        _test_exercise_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_Success(_data[1], wbtcUSDCMiningPool, 1000000e8, wbtc, usdc);
    }
}
