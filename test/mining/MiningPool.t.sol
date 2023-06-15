// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ONE} from "contracts/libraries/Constants.sol";
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
        _data[1] = Data(ud(0.1e18), ud(30000e18), ud(35000e18), ud(0.20e18), 60 days, 90 days, 30 days);
        //        data[2] = Data(0.90e18,  ud(0.80e18), 30 days, 30 days, 365 days);

        premia = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70; // PREMIA (18 decimals)
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // PREMIA (18 decimals)
        wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC (8 decimals)
        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC (6 decimals)

        premiaUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                premia,
                usdc,
                users.underwriter,
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
                users.underwriter,
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

    function getMaturity(uint256 timestamp, uint256 expiryDuration) internal pure returns (uint256 maturity) {
        maturity = timestamp - (timestamp % 24 hours) + 8 hours + expiryDuration;
    }

    function setPriceAt(uint256 timestamp, UD60x18 price, address base, address quote) internal {
        vm.prank(users.keeper);
        priceRepository.setPriceAt(base, quote, timestamp, price);
    }

    function scaleDecimalsFrom(address token, uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    function scaleDecimalsTo(address token, UD60x18 amount) internal view returns (uint256) {
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
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        uint256 collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), collateral);
    }

    function test_writeFrom_Success() public {
        _test_writeFrom_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_writeFrom_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_writeFrom_OnBehalfOfUnderwriter(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        uint256 collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.setApprovalForAll(users.longReceiver, true);
        vm.stopPrank();

        vm.startPrank(users.longReceiver);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), collateral);
    }

    function test_writeFrom_OnBehalfOfUnderwriter() public {
        _test_writeFrom_OnBehalfOfUnderwriter(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_writeFrom_OnBehalfOfUnderwriter(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function test_writeFrom_RevertIf_OperatorNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__OperatorNotAuthorized.selector, users.longReceiver)
        );

        vm.prank(users.longReceiver);
        premiaUSDCMiningPool.writeFrom(users.underwriter, users.longReceiver, ud(1000000e18));
    }

    function _test_exercise_PhysicallySettled_Success(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        uint256 collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        UD60x18 _strike = data.discount * data.spot;
        int128 strike = _strike.unwrap().toInt256().toInt128();

        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        vm.startPrank(users.longReceiver);
        uint256 exerciseCost = scaleDecimalsTo(quote, (_size * _strike));
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
        assertEq(IERC20(quote).balanceOf(address(users.underwriter)), 0);

        // TODO: assertEq(IERC20(quote).balanceOf(address(vxPREMIA)), 0.9e18 * exerciseCost);
        // TODO: assertEq(IERC20(quote).balanceOf(address(TREASURY)), 0.1e18 * exerciseCost);

        assertEq(IERC20(base).balanceOf(address(users.longReceiver)), collateral);
        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), 0);
    }

    function test_exercise_PhysicallySettled_Success() public {
        _test_exercise_PhysicallySettled_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_PhysicallySettled_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    // TODO: Fuzz test?
    function _test_exercise_CashSettled_Success(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        uint256 collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        {
            uint256 lockupStart = maturity + data.exerciseDuration;
            uint256 lockupEnd = lockupStart + data.lockupDuration;
            vm.warp(lockupEnd);
        }

        UD60x18 _strike = data.discount * data.spot;

        uint256 exerciseValue;
        {
            UD60x18 intrinsicValue = (data.settlementITM - _strike);
            UD60x18 _exerciseValue = (_size * intrinsicValue) / data.settlementITM;
            _exerciseValue = _exerciseValue * (ONE - data.penalty);
            exerciseValue = scaleDecimalsTo(base, _exerciseValue);
        }

        uint256 longTokenId = miningPool.formatTokenId(
            IMiningPool.TokenType.LONG,
            maturity,
            _strike.unwrap().toInt256().toInt128()
        );

        uint256 shortTokenId = miningPool.formatTokenId(
            IMiningPool.TokenType.SHORT,
            maturity,
            _strike.unwrap().toInt256().toInt128()
        );

        vm.prank(users.longReceiver);
        miningPool.exercise(longTokenId, _size);

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), 0);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), 0);
        assertEq(IERC20(quote).balanceOf(address(users.underwriter)), 0);

        // TODO: assertEq(IERC20(quote).balanceOf(address(vxPREMIA)), 0);
        // TODO: assertEq(IERC20(quote).balanceOf(address(TREASURY)), 0);

        assertEq(IERC20(base).balanceOf(address(users.longReceiver)), exerciseValue);
        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), collateral - exerciseValue);
    }

    function test_exercise_CashSettled_Success() public {
        _test_exercise_CashSettled_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_CashSettled_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_exercise_RevertIf_TokenTypeNotLong(Data storage data, MiningPool miningPool) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        vm.expectRevert(IMiningPool.MiningPool__TokenTypeNotLong.selector);
        miningPool.exercise(shortTokenId, ud(1000000e18));
    }

    function test_exercise_RevertIf_TokenTypeNotLong() public {
        _test_exercise_RevertIf_TokenTypeNotLong(_data[0], premiaUSDCMiningPool);
        _test_exercise_RevertIf_TokenTypeNotLong(_data[1], wbtcUSDCMiningPool);
    }

    function _test_exercise_RevertIf_OptionNotExpired(Data storage data, MiningPool miningPool) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);

        vm.expectRevert(abi.encodeWithSelector(IMiningPool.MiningPool__OptionNotExpired.selector, maturity));
        vm.warp(maturity - 1);
        miningPool.exercise(longTokenId, ud(1000000e18));
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        _test_exercise_RevertIf_OptionNotExpired(_data[0], premiaUSDCMiningPool);
        _test_exercise_RevertIf_OptionNotExpired(_data[1], wbtcUSDCMiningPool);
    }

    function _test_exercise_RevertIf_OptionOutTheMoney(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        uint256 collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        vm.warp(maturity);

        UD60x18 _strike = data.discount * data.spot;
        int128 strike = _strike.unwrap().toInt256().toInt128();
        UD60x18 settlementOTM = _strike.sub(ud(1));
        setPriceAt(maturity, settlementOTM, base, quote);

        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);

        vm.startPrank(users.longReceiver);
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__OptionOutTheMoney.selector, settlementOTM, _strike)
        );

        miningPool.exercise(longTokenId, _size);
        vm.stopPrank();
    }

    function test_exercise_RevertIf_OptionOutTheMoney() public {
        _test_exercise_RevertIf_OptionOutTheMoney(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_RevertIf_OptionOutTheMoney(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_exercise_RevertIf_LockupNotExpired(
        Data storage data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        uint256 collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.writeFrom(users.underwriter, users.longReceiver, _size);
        vm.stopPrank();

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        uint256 lockupStart = maturity + data.exerciseDuration;
        uint256 lockupEnd = lockupStart + data.lockupDuration;

        vm.warp(lockupStart);

        int128 strike = (data.discount * data.spot).unwrap().toInt256().toInt128();
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);

        vm.startPrank(users.longReceiver);
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__LockupNotExpired.selector, lockupStart, lockupEnd)
        );

        miningPool.exercise(longTokenId, _size);
        vm.stopPrank();
    }

    function test_exercise_RevertIf_LockupNotExpired() public {
        _test_exercise_RevertIf_LockupNotExpired(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_RevertIf_LockupNotExpired(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }
}
